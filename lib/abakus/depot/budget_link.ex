defmodule Abakus.Depot.BudgetLink do
  @moduledoc """
  Depot cash flows linked to the budget (ADR 0020), as the Kasse's expenses are. Once the budget owner
  switches it on, every flow between one of their portfolios and a Verrechnungskonto that is a budget account
  (`Abakus.Depot.AccountRoles`) is a linked transaction in that budget account, written through the Ledger with
  their scope:

    * a purchase, or a cash transfer into a portfolio's cash, is an outflow in the link's category;
    * a sale, or a cash transfer out of a portfolio's cash, is an inflow to Ready to Assign;
    * both are transfers to the portfolio's tracking account, so its balance moves with the portfolio's value and
      the daily value change (`Abakus.Depot.BudgetFeed`) keeps only the market movement;
    * a dividend is an inflow to Ready to Assign from the security, as it leaves the portfolio's value alone.

  Only transactions dated on or after the link's start date count. The linked transaction refers to its Depot
  transaction, which leads amount, date, payee and account: the Ledger refuses them to anyone else. Category, memo,
  cleared state and approval are the register's after the first write. `sync/1` runs in the database transaction of
  every Depot write; `release/2` removes a Depot transaction's linked one before the Depot transaction goes.
  """

  import Ecto.Query

  alias Abakus.Categories
  alias Abakus.Categories.Category
  alias Abakus.Depot.BudgetLink.Link
  alias Abakus.Depot.Portfolios.{Account, Portfolio, Transaction}
  alias Abakus.{Ledger, LocalTime, Repo}
  alias Abakus.Ledger.Transaction, as: LedgerTransaction
  alias Abakus.Users.{Scope, User}
  alias Ecto.Changeset

  @types [:buy, :sell, :dividend, :cash_transfer]

  @doc "The user's link, nil while it is off."
  def get(%Scope{user: %User{id: id}}), do: Repo.get(Link, id)

  @doc "A changeset for switching the link on, starting today."
  def change_link(attrs \\ %{}),
    do: Link.changeset(%Link{start_date: LocalTime.today()}, attrs)

  @doc "The user's regular budget categories purchases can be booked in, grouped for a select."
  def category_options(%Scope{} = scope) do
    for %{categories: [_ | _] = categories} = group <- Categories.list_category_groups(scope),
        do: {group.name, Enum.map(categories, &{&1.name, &1.id})}
  end

  @doc """
  Switches the link on for the budget owner with `category_id` and `start_date`, and links their Depot transactions
  since then. Returns `{:ok, link}`, `{:error, changeset}`, `{:error, :not_budget_owner}`, `{:error, :linked}` or
  `{:error, message}` when a linked transaction cannot be written.
  """
  def switch_on(%Scope{} = scope, attrs) do
    if Scope.budget_owner?(scope),
      do: Repo.transact(fn -> link(scope, attrs) end),
      else: {:error, :not_budget_owner}
  end

  defp link(%Scope{user: user} = scope, attrs) do
    with :ok <- if(Repo.get(Link, user.id), do: {:error, :linked}, else: :ok),
         {:ok, link} <-
           %Link{user_id: user.id}
           |> Link.changeset(attrs)
           |> validate_category()
           |> Repo.insert(),
         :ok <- sync(scope) do
      {:ok, link}
    end
  end

  @doc """
  Changes the category of the user's later purchases; linked transactions keep theirs. Returns `{:ok, link}`,
  `{:error, changeset}` or `{:error, :not_linked}`.
  """
  def change_category(%Scope{} = scope, category_id) do
    case get(scope) do
      nil ->
        {:error, :not_linked}

      link ->
        link
        |> Link.changeset(%{category_id: category_id})
        |> validate_category()
        |> Repo.update()
    end
  end

  defp validate_category(%Changeset{data: %Link{user_id: user_id}} = changeset) do
    Changeset.validate_change(changeset, :category_id, fn :category_id, id ->
      if Repo.exists?(
           from c in Category, where: c.id == ^id and c.user_id == ^user_id and not c.internal
         ),
         do: [],
         else: [category_id: "ist keine Kategorie des Budgets"]
    end)
  end

  @doc "Moves the user's link's category from one budget category to another, as deleting `from_id` does."
  def recategorize(%Scope{user: %User{id: user_id}}, from_id, to_id) do
    Repo.update_all(where(Link, user_id: ^user_id, category_id: ^from_id),
      set: [category_id: to_id]
    )

    :ok
  end

  @doc """
  Brings the scope's user's linked transactions in line with their Depot transactions, inside the caller's
  database transaction. Returns `:ok` or `{:error, message}`, in German.
  """
  def sync(%Scope{user: %User{id: user_id}} = scope) do
    link = Repo.get(Link, user_id)
    wanted = if link, do: wanted_by_depot_transaction(link), else: %{}
    linked = Map.new(Repo.all(linked_transactions(user_id)), &{&1.depot_transaction_id, &1})

    with :ok <- each(Map.drop(linked, Map.keys(wanted)), &remove(scope, &1)) do
      each(Enum.sort(wanted), fn {id, wanted} -> write(scope, link, id, linked[id], wanted) end)
    end
  end

  @doc """
  Removes the linked transaction of the scope's user's Depot transaction, inside the caller's database transaction,
  before the Depot transaction is deleted. Returns `:ok` or `{:error, message}`, in German.
  """
  def release(%Scope{user: %User{id: user_id}} = scope, %Transaction{id: id}) do
    linked = Repo.all(where(linked_transactions(user_id), [t], t.depot_transaction_id == ^id))
    each(Enum.map(linked, &{id, &1}), &remove(scope, &1))
  end

  defp linked_transactions(user_id),
    do:
      from(t in LedgerTransaction,
        where:
          t.user_id == ^user_id and not is_nil(t.depot_transaction_id) and is_nil(t.deleted_at)
      )

  defp remove(scope, {id, linked}) do
    with {:ok, _deleted} <- Ledger.delete_transaction(scope, linked, opts(id)), do: :ok
  end

  defp opts(depot_transaction_id),
    do: [reconciled: :confirmed, led_by: {:depot_transaction, depot_transaction_id}]

  defp each(items, fun) do
    Enum.reduce_while(items, :ok, fn item, :ok ->
      case fun.(item) do
        :ok -> {:cont, :ok}
        {:error, %Changeset{} = changeset} -> {:halt, {:error, refused(changeset)}}
        {:error, reason} -> {:halt, {:error, inspect(reason)}}
      end
    end)
  end

  defp write(scope, link, depot_transaction_id, nil, wanted) do
    with {:ok, _transaction} <-
           Ledger.create_transaction(scope, new_attrs(scope, link, wanted),
             led_by: {:depot_transaction, depot_transaction_id}
           ) do
      :ok
    end
  end

  defp write(scope, _link, depot_transaction_id, linked, wanted) do
    attrs =
      wanted
      |> Map.take([:account_id, :amount, :date])
      |> Map.merge(payee_attrs(scope, wanted.payee))
      |> Enum.reject(fn {field, value} -> Map.get(linked, field) == value end)
      |> Map.new()

    if attrs == %{},
      do: :ok,
      else: rewrite(scope, linked, attrs, opts(depot_transaction_id))
  end

  defp rewrite(scope, linked, attrs, opts) do
    with {:ok, _transaction} <- Ledger.update_transaction(scope, linked, attrs, opts), do: :ok
  end

  defp new_attrs(scope, link, wanted) do
    wanted
    |> Map.take([:account_id, :amount, :date, :memo])
    |> Map.merge(payee_attrs(scope, wanted.payee))
    |> Map.merge(%{
      category_id:
        if(wanted.amount < 0,
          do: link.category_id,
          else: Categories.ready_to_assign!(scope).id
        ),
      cleared: :uncleared,
      source: :depot
    })
  end

  defp payee_attrs(_scope, {:transfer, payee_id}), do: %{payee_id: payee_id}

  defp payee_attrs(scope, {:name, name}) do
    case Ledger.find_payee_by_name(scope, name) do
      %{transfer_account_id: nil, id: id} -> %{payee_id: id}
      _none -> %{payee_name: name}
    end
  end

  defp wanted_by_depot_transaction(%Link{} = link) do
    context = context(link.user_id)
    since = NaiveDateTime.new!(link.start_date, ~T[00:00:00])

    from(t in Transaction,
      where: t.user_id == ^link.user_id and t.type in ^@types and t.date_time >= ^since,
      preload: [:security, :units]
    )
    |> Repo.all()
    |> Enum.flat_map(fn transaction ->
      case wanted(transaction, context) do
        nil -> []
        wanted -> [{transaction.id, Map.put(wanted, :date, date(transaction))}]
      end
    end)
    |> Map.new()
  end

  defp context(user_id) do
    accounts = Repo.all(from a in Account, where: a.user_id == ^user_id)

    portfolios =
      Repo.all(
        from p in Portfolio,
          where: p.user_id == ^user_id,
          preload: [budget_account: :transfer_payee]
      )

    %{
      budget_accounts:
        for(a <- accounts, a.budget_account_id, into: %{}, do: {a.id, a.budget_account_id}),
      cash_of:
        for(a <- accounts, a.cash_of_portfolio_id, into: %{}, do: {a.id, a.cash_of_portfolio_id}),
      portfolios: Map.new(portfolios, &{&1.id, &1})
    }
  end

  defp wanted(%Transaction{type: :buy} = t, context),
    do: portfolio_flow(context, t.account_id, t.portfolio_id, -t.amount, memo("Kauf", t))

  defp wanted(%Transaction{type: :sell} = t, context),
    do: portfolio_flow(context, t.account_id, t.portfolio_id, t.amount, memo("Verkauf", t))

  defp wanted(%Transaction{type: :dividend, security: %{name: name}} = t, context) do
    if account_id = context.budget_accounts[t.account_id],
      do: %{account_id: account_id, amount: t.amount, payee: {:name, name}, memo: "Dividende"}
  end

  defp wanted(%Transaction{type: :cash_transfer} = t, context) do
    cond do
      portfolio_id = context.cash_of[t.other_account_id] ->
        portfolio_flow(context, t.account_id, portfolio_id, -t.amount, "Einzahlung")

      portfolio_id = context.cash_of[t.account_id] ->
        portfolio_flow(context, t.other_account_id, portfolio_id, t.amount, "Entnahme")

      true ->
        nil
    end
  end

  defp wanted(_transaction, _context), do: nil

  defp portfolio_flow(context, account_id, portfolio_id, amount, memo) do
    with budget_account_id when budget_account_id != nil <- context.budget_accounts[account_id],
         %Portfolio{} = portfolio <- context.portfolios[portfolio_id] do
      %{account_id: budget_account_id, amount: amount, payee: payee(portfolio), memo: memo}
    else
      _none -> nil
    end
  end

  defp payee(%Portfolio{budget_account: %{transfer_payee: %{id: id}}}), do: {:transfer, id}
  defp payee(%Portfolio{name: name}), do: {:name, name}

  defp memo(kind, %Transaction{security: %{name: name}}), do: "#{kind} #{name}"
  defp memo(kind, _transaction), do: kind

  defp date(%Transaction{date_time: date_time}), do: NaiveDateTime.to_date(date_time)

  defp refused(changeset) do
    errors =
      changeset
      |> Changeset.traverse_errors(fn {message, _opts} -> message end)
      |> Enum.flat_map(fn {field, messages} -> Enum.map(messages, &"#{field} #{&1}") end)
      |> Enum.join(", ")

    "Die Buchung im Budget ließ sich nicht schreiben (#{errors})."
  end
end
