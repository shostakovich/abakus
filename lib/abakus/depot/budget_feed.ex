defmodule Abakus.Depot.BudgetFeed do
  @moduledoc """
  The budget owner's portfolios and Verrechnungskonten in the budget: each feeds at most one open tracking
  account, which is then fed by `portfolio`. Every day after the price job, `book_value_changes/1` books the
  difference between what an account's portfolios and Verrechnungskonten are worth and its balance as one value
  change through the Ledger; nothing else writes to such an account.
  """

  import Ecto.Query

  require Logger

  alias Abakus.Depot.BudgetFeed.Feed
  alias Abakus.Depot.Portfolios
  alias Abakus.Depot.Portfolios.{Account, Portfolio}
  alias Abakus.{Ledger, LocalTime, Repo}
  alias Abakus.Ledger.Account, as: BudgetAccount
  alias Abakus.Ledger.Transaction
  alias Abakus.Users.{Scope, User}

  @payee "Wertänderung"

  @doc "The accounts a portfolio or Verrechnungskonto can feed: open tracking accounts not fed by the Kasse, in order."
  def account_choices do
    Repo.all(
      from a in BudgetAccount,
        where: a.kind == :tracking and not a.closed,
        where: is_nil(a.fed_by) or a.fed_by == :portfolio,
        order_by: [a.position, a.id]
    )
  end

  @doc """
  The accounts in `feeds` (as `feeds/1` gives them) that `account_choices/0` leaves out, e.g. closed ones, in
  order: they stay selectable for the portfolio or Verrechnungskonto that already feeds them.
  """
  def fed_accounts_not_offered(feeds) do
    offered = Enum.map(account_choices(), & &1.id)
    ids = feeds |> Map.values() |> Enum.reject(&(&1 in offered))
    Repo.all(from a in BudgetAccount, where: a.id in ^ids, order_by: [a.position, a.id])
  end

  @doc """
  Which of the user's portfolios and Verrechnungskonten feed which account, as the account id by
  `{:portfolio, id}` or `{:account, id}`.
  """
  def feeds(%Scope{user: %User{id: user_id}}) do
    Repo.all(
      from f in Feed,
        left_join: p in assoc(f, :portfolio),
        left_join: a in assoc(f, :depot_account),
        where: p.user_id == ^user_id or a.user_id == ^user_id,
        select: {f.portfolio_id, f.depot_account_id, f.account_id}
    )
    |> Map.new(fn
      {nil, depot_account_id, account_id} -> {{:account, depot_account_id}, account_id}
      {portfolio_id, nil, account_id} -> {{:portfolio, portfolio_id}, account_id}
    end)
  end

  @doc "Whether anything feeds the budget, which a wipe of the budget would drop."
  def in_use?, do: Repo.exists?(Feed)

  @doc """
  Sets which account the budget owner's portfolios and Verrechnungskonten feed: account ids (one of
  `account_choices/0` or the one it already feeds, nil or `""` for none) by `{:portfolio, id}` or `{:account, id}`, ids also as text; those left
  out keep theirs. An account fed by something is fed by `portfolio`, one fed by nothing any more by nobody.
  Returns `{:ok, feeds}` as `feeds/1` gives them, or `{:error, reason}`: `:not_budget_owner` or `:unknown`.
  """
  def put_feeds(%Scope{user: user} = scope, feeds) do
    with :ok <- check_budget_owner(user),
         {:ok, feeds} <- cast_feeds(feeds),
         :ok <- check_feeds(scope, feeds) do
      Repo.transact(fn ->
        replace_feeds(feeds)
        mark_fed_accounts()
        {:ok, feeds(scope)}
      end)
    end
  end

  defp check_budget_owner(%User{budget_owner: true}), do: :ok
  defp check_budget_owner(_user), do: {:error, :not_budget_owner}

  defp cast_feeds(feeds) do
    Enum.reduce_while(feeds, {:ok, %{}}, fn {{kind, id}, account_id}, {:ok, cast} ->
      with true <- kind in [:portfolio, :account],
           {:ok, id} <- Abakus.Schema.cast_id(id),
           {:ok, account_id} <- cast_account_id(account_id) do
        {:cont, {:ok, Map.put(cast, {kind, id}, account_id)}}
      else
        _invalid -> {:halt, {:error, :unknown}}
      end
    end)
  end

  defp cast_account_id(id) when id in [nil, ""], do: {:ok, nil}
  defp cast_account_id(id), do: Abakus.Schema.cast_id(id)

  defp check_feeds(%Scope{user: %User{id: user_id}} = scope, feeds) do
    current = feeds(scope)

    owned = %{
      portfolio: Repo.all(from p in Portfolio, where: p.user_id == ^user_id, select: p.id),
      account: Repo.all(from a in Account, where: a.user_id == ^user_id, select: a.id)
    }

    choices = Enum.map(account_choices(), & &1.id)

    if Enum.all?(feeds, fn {{kind, id}, account_id} ->
         id in owned[kind] and
           (account_id == nil or account_id in choices or current[{kind, id}] == account_id)
       end),
       do: :ok,
       else: {:error, :unknown}
  end

  defp replace_feeds(feeds) do
    {portfolio_ids, account_ids} = Enum.split_with(Map.keys(feeds), &match?({:portfolio, _}, &1))

    Repo.delete_all(
      from f in Feed,
        where:
          f.portfolio_id in ^Enum.map(portfolio_ids, &elem(&1, 1)) or
            f.depot_account_id in ^Enum.map(account_ids, &elem(&1, 1))
    )

    now = DateTime.utc_now()

    Repo.insert_all(
      Feed,
      for {{kind, id}, account_id} <- feeds, account_id do
        %{
          account_id: account_id,
          portfolio_id: if(kind == :portfolio, do: id),
          depot_account_id: if(kind == :account, do: id),
          inserted_at: now,
          updated_at: now
        }
      end
    )
  end

  @doc """
  Marks the accounts something feeds as fed by `portfolio` and frees those nothing feeds any more, e.g. after a
  PP import deleted the portfolio or Verrechnungskonto that fed them.
  """
  def mark_fed_accounts do
    fed = from f in Feed, select: f.account_id

    Repo.update_all(
      from(a in BudgetAccount, where: a.fed_by == :portfolio and a.id not in subquery(fed)),
      set: [fed_by: nil]
    )

    Repo.update_all(from(a in BudgetAccount, where: a.id in subquery(fed)),
      set: [fed_by: :portfolio]
    )
  end

  @doc """
  Books into every open account fed by the budget owner's portfolios and Verrechnungskonten the difference
  between what they are worth on `date` and the account's balance up to `date`: one transaction dated `date`, payee
  "Wertänderung", approved and cleared; none without a difference. Another run on the same day amends that
  transaction, and deletes it once its amount is 0. A refused booking is logged and leaves the other accounts
  alone.
  """
  def book_value_changes(%Date{} = date \\ LocalTime.today()) do
    with %User{} = owner <- Repo.get_by(User, budget_owner: true) do
      scope = Scope.for_user(owner)
      Enum.each(fed_accounts(scope), &book_value_change(scope, &1, date))
    end

    :ok
  end

  defp fed_accounts(%Scope{user: %User{id: user_id}}) do
    Repo.all(
      from f in Feed,
        join: b in assoc(f, :account),
        left_join: p in assoc(f, :portfolio),
        left_join: a in assoc(f, :depot_account),
        where: p.user_id == ^user_id or a.user_id == ^user_id,
        where: b.fed_by == :portfolio and not b.closed,
        preload: [account: b]
    )
    |> Enum.group_by(& &1.account)
  end

  defp booked_change(account, date) do
    Repo.one(
      from t in Ledger.in_register(),
        where: t.account_id == ^account.id and t.date == ^date and t.source == :depot,
        order_by: t.id,
        limit: 1
    )
  end

  defp book_value_change(scope, {account, feeds}, date) do
    value =
      Portfolios.value(
        scope,
        for(%Feed{portfolio_id: id} <- feeds, id, do: id),
        for(%Feed{depot_account_id: id} <- feeds, id, do: id),
        date
      )

    balance = Ledger.balance(account, date)
    if value != balance, do: book(account, value - balance, date), else: :ok
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
