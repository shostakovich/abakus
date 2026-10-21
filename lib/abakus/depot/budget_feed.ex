defmodule Abakus.Depot.BudgetFeed do
  @moduledoc """
  The budget owner's portfolios in the budget: each is one tracking account fed by `portfolio`, its
  `budget_account` (ADR 0017); an account fed by `portfolio` that no portfolio has is closed. Every day after the
  price job, `book_value_changes/1` books the difference between the value of a portfolio's holdings and its
  account's balance as one value change through the Ledger; nothing else writes to such an account, as the cash has
  accounts of its own (`Abakus.Depot.CashSide`). It writes with the budget owner's scope.
  """

  import Ecto.Query

  require Logger

  alias Abakus.Depot.Portfolios
  alias Abakus.Depot.Portfolios.Portfolio
  alias Abakus.{Ledger, LocalTime, Names, Repo}
  alias Abakus.Ledger.Account
  alias Abakus.Ledger.Transaction
  alias Abakus.Users.{Scope, User}

  @payee "Wertänderung"

  @doc "The user's portfolio whose account `account` is, nil for any other account."
  def portfolio(%Scope{user: %User{id: user_id}}, %Account{fed_by: :portfolio, id: id}),
    do: Repo.get_by(Portfolio, budget_account_id: id, user_id: user_id)

  def portfolio(%Scope{}, %Account{}), do: nil

  @doc """
  Opens the tracking account of a portfolio of the budget owner, named after it, and returns the portfolio with
  its `budget_account_id`; another user's portfolio stays without one.
  """
  def open_account(%Scope{} = scope, %Portfolio{budget_account_id: nil} = portfolio) do
    if Scope.budget_owner?(scope),
      do: open_tracking_account(scope, portfolio),
      else: {:ok, portfolio}
  end

  def open_account(%Scope{}, %Portfolio{} = portfolio), do: {:ok, portfolio}

  defp open_tracking_account(scope, portfolio) do
    Repo.transact(fn ->
      with {:ok, account} <-
             Ledger.create_account(scope, %{
               name: portfolio.name,
               kind: :tracking,
               fed_by: :portfolio
             }) do
        portfolio |> Ecto.Changeset.change(budget_account_id: account.id) |> Repo.update()
      end
    end)
  end

  @doc """
  Opens the account of every active portfolio of the budget owner without one, names each account after its
  portfolio, keeping a leading emoji of the account's name, and closes the accounts fed by `portfolio` that no
  portfolio has any more, keeping their history: a last value change dated `date` takes each to 0, as the new
  accounts get their portfolio's value with the next value change.
  """
  def sync_accounts(%Date{} = date \\ LocalTime.today()) do
    with %Scope{} = owner <- Scope.for_budget_owner() do
      close_accounts_without_portfolio(owner, date)
      rename_accounts(owner)

      for portfolio <- Repo.all(untied_portfolios(owner)),
          do: {:ok, _portfolio} = open_account(owner, portfolio)
    end

    :ok
  end

  defp untied_portfolios(owner),
    do:
      from(p in Portfolio,
        where: p.user_id == ^owner.user.id and not p.retired and is_nil(p.budget_account_id)
      )

  defp rename_accounts(owner) do
    for {portfolio, account} <-
          Repo.all(
            from p in Portfolio,
              join: a in Account,
              on: a.id == p.budget_account_id,
              where: a.user_id == ^owner.user.id,
              select: {p, a}
          ),
        name = account_name(account.name, portfolio.name),
        name != account.name,
        do: {:ok, _account} = Ledger.update_account(owner, account, %{name: name})
  end

  defp account_name(current, name) when is_binary(name) do
    case Names.split_emoji(current) do
      {nil, _rest} -> name
      {emoji, _rest} -> "#{emoji} #{name}"
    end
  end

  defp account_name(_current, name), do: name

  defp close_accounts_without_portfolio(owner, date) do
    tied =
      from p in Portfolio, where: not is_nil(p.budget_account_id), select: p.budget_account_id

    for account <-
          Repo.all(
            from a in Account,
              where:
                a.user_id == ^owner.user.id and a.fed_by == :portfolio and not a.closed and
                  a.id not in subquery(tied)
          ) do
      balance = Ledger.balance(owner, account, date)
      if balance != 0, do: book(owner, account, -balance, date)
      {:ok, _closed} = Ledger.update_account(owner, account, %{closed: true})
    end
  end

  @doc """
  Books into the open account of every portfolio of the budget owner the difference between the value of the
  portfolio's holdings on `date` and the account's balance up to `date`: one transaction dated `date`, payee
  "Wertänderung", approved and cleared; none without a difference, so a new account starts at its portfolio's value.
  Another run on the same day amends that transaction, and deletes it once its amount is 0. A refused booking is
  logged and leaves the other accounts alone. Syncs the accounts first (`sync_accounts/0`).
  """
  def book_value_changes(%Date{} = date \\ LocalTime.today()) do
    sync_accounts(date)

    with %Scope{} = owner <- Scope.for_budget_owner() do
      for {portfolio, account} <- portfolio_accounts(owner),
          do: book_value_change(owner, portfolio, account, date)
    end

    :ok
  end

  defp portfolio_accounts(owner) do
    Repo.all(
      from p in Portfolio,
        join: a in Account,
        on: a.id == p.budget_account_id,
        where: p.user_id == ^owner.user.id and a.fed_by == :portfolio and not a.closed,
        order_by: p.id,
        select: {p, a}
    )
  end

  defp book_value_change(scope, portfolio, account, date) do
    value = Portfolios.value(scope, [portfolio.id], [], date)
    balance = Ledger.balance(scope, account, date)
    if value != balance, do: book(scope, account, value - balance, date), else: :ok
  end

  defp booked_change(scope, account, date) do
    Repo.one(
      from t in Ledger.in_register(scope),
        where:
          t.account_id == ^account.id and t.date == ^date and t.source == :depot and
            is_nil(t.transfer_transaction_id),
        order_by: t.id,
        limit: 1
    )
  end

  defp book(scope, account, change, date) do
    case booked_change(scope, account, date) do
      nil ->
        Ledger.create_transaction(scope, %{
          account_id: account.id,
          date: date,
          amount: change,
          payee_name: @payee,
          cleared: :cleared,
          approved: true,
          source: :depot
        })

      %Transaction{amount: amount} = booked when amount + change == 0 ->
        Ledger.delete_transaction(scope, booked)

      booked ->
        Ledger.update_transaction(scope, booked, %{amount: booked.amount + change})
    end
    |> case do
      {:ok, _transaction} ->
        :ok

      {:error, changeset} ->
        Logger.error(
          "The value change of account #{account.id} was refused: #{inspect(changeset)}"
        )
    end
  end
end
