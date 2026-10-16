defmodule Abakus.Depot.BudgetFeed do
  @moduledoc """
  The budget owner's portfolios in the budget: each is one tracking account fed by `portfolio`, its
  `budget_account` (ADR 0017); an account fed by `portfolio` that no portfolio has is closed, as were those that
  several portfolios fed before. Every day after the price job, `book_value_changes/1` books the difference between a
  portfolio's value and its account's balance as one value change through the Ledger; nothing else writes to such
  an account.
  """

  import Ecto.Query

  require Logger

  alias Abakus.Depot.Portfolios
  alias Abakus.Depot.Portfolios.Portfolio
  alias Abakus.{Ledger, LocalTime, Repo}
  alias Abakus.Ledger.Account
  alias Abakus.Ledger.Transaction
  alias Abakus.Users.{Scope, User}

  @payee "Wertänderung"

  @doc "Whether a portfolio has an account in the budget, which a wipe of the budget would drop."
  def in_use?, do: Repo.exists?(from p in Portfolio, where: not is_nil(p.budget_account_id))

  @doc "The portfolio whose account `account` is, nil for any other account."
  def portfolio(%Account{fed_by: :portfolio, id: id}),
    do: Repo.get_by(Portfolio, budget_account_id: id)

  def portfolio(%Account{}), do: nil

  @doc """
  Opens the tracking account of a portfolio of the budget owner, named after it, and returns the portfolio with
  its `budget_account_id`; another user's portfolio stays without one.
  """
  def open_account(%Portfolio{budget_account_id: nil} = portfolio, %User{budget_owner: true}) do
    Repo.transact(fn ->
      with {:ok, account} <-
             Ledger.create_account(%{name: portfolio.name, kind: :tracking, fed_by: :portfolio}) do
        portfolio |> Ecto.Changeset.change(budget_account_id: account.id) |> Repo.update()
      end
    end)
  end

  def open_account(%Portfolio{} = portfolio, %User{}), do: {:ok, portfolio}

  @doc """
  Opens the account of every active portfolio of the budget owner without one, names each account after its
  portfolio and closes the accounts fed by `portfolio` that no portfolio has any more, keeping their history: a
  last value change dated `date` takes each to 0, as the new accounts get their portfolio's value with the next
  value change.
  """
  def sync_accounts(%Date{} = date \\ LocalTime.today()) do
    close_accounts_without_portfolio(date)
    rename_accounts()

    with %User{} = owner <- budget_owner() do
      for portfolio <- Repo.all(untied_portfolios(owner)),
          do: {:ok, _portfolio} = open_account(portfolio, owner)
    end

    :ok
  end

  defp untied_portfolios(%User{id: user_id}),
    do:
      from(p in Portfolio,
        where: p.user_id == ^user_id and not p.retired and is_nil(p.budget_account_id)
      )

  defp rename_accounts do
    for {portfolio, account} <-
          Repo.all(
            from p in Portfolio,
              join: a in Account,
              on: a.id == p.budget_account_id,
              where: a.name != p.name,
              select: {p, a}
          ),
        do: {:ok, _account} = Ledger.update_account(account, %{name: portfolio.name})
  end

  defp close_accounts_without_portfolio(date) do
    tied =
      from p in Portfolio, where: not is_nil(p.budget_account_id), select: p.budget_account_id

    for account <-
          Repo.all(
            from a in Account,
              where: a.fed_by == :portfolio and not a.closed and a.id not in subquery(tied)
          ) do
      balance = Ledger.balance(account, date)
      if balance != 0, do: book(account, -balance, date)
      {:ok, _closed} = Ledger.update_account(account, %{closed: true})
    end
  end

  defp budget_owner, do: Repo.get_by(User, budget_owner: true)

  @doc """
  Books into the open account of every portfolio of the budget owner the difference between the portfolio's value
  on `date` and the account's balance up to `date`: one transaction dated `date`, payee "Wertänderung", approved
  and cleared; none without a difference, so a new account starts at its portfolio's value. Another run on the same
  day amends that transaction, and deletes it once its amount is 0. A refused booking is logged and leaves the
  other accounts alone. Syncs the accounts first (`sync_accounts/0`).
  """
  def book_value_changes(%Date{} = date \\ LocalTime.today()) do
    sync_accounts(date)

    with %User{} = owner <- budget_owner() do
      scope = Scope.for_user(owner)

      for {portfolio, account} <- portfolio_accounts(owner),
          do: book_value_change(scope, portfolio, account, date)
    end

    :ok
  end

  defp portfolio_accounts(%User{id: user_id}) do
    Repo.all(
      from p in Portfolio,
        join: a in Account,
        on: a.id == p.budget_account_id,
        where: p.user_id == ^user_id and a.fed_by == :portfolio and not a.closed,
        order_by: p.id,
        select: {p, a}
    )
  end

  defp book_value_change(scope, portfolio, account, date) do
    value = Portfolios.value(scope, [portfolio.id], [], date)
    balance = Ledger.balance(account, date)
    if value != balance, do: book(account, value - balance, date), else: :ok
  end

  defp booked_change(account, date) do
    Repo.one(
      from t in Ledger.in_register(),
        where: t.account_id == ^account.id and t.date == ^date and t.source == :depot,
        order_by: t.id,
        limit: 1
    )
  end

  defp book(account, change, date) do
    case booked_change(account, date) do
      nil ->
        Ledger.create_transaction(%{
          account_id: account.id,
          date: date,
          amount: change,
          payee_name: @payee,
          cleared: :cleared,
          approved: true,
          source: :depot
        })

      %Transaction{amount: amount} = booked when amount + change == 0 ->
        Ledger.delete_transaction(booked)

      booked ->
        Ledger.update_transaction(booked, %{amount: booked.amount + change})
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
