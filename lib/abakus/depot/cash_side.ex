defmodule Abakus.Depot.CashSide do
  @moduledoc """
  The money of the Depot in the Ledger (ADR 0020). Every Verrechnungskonto has its Ledger account: the budget account
  of its budget account role, else a tracking account of its own, named after it and closed when it is retired or
  the cash of a retired portfolio. Each Depot transaction's cash side is a Ledger transaction it leads, written with
  the user's scope; a cash transfer between two Verrechnungskonten is a Ledger transfer, led from its budget side if
  it has one.

    * Into a tracking account goes the whole history, cleared and approved, without category.
    * Into a budget account go, while the Depot link is on (`Abakus.Depot.BudgetLink`), purchases, sales, dividends
      and cash transfers dated from its start date on, uncleared and unapproved: outflows in the link's category,
      inflows to Ready to Assign, none for a transfer between budget accounts. The bank import holds the rest.

  Purchases and sales are with the portfolio, other transactions with their security, a cash transfer's side
  without the other with that account. The source leads amount, date, account and payee; category, memo, cleared
  state and approval are the register's after the first write. `sync/1` runs in the database transaction of every
  Depot write, `release/2` before a Depot transaction is deleted.
  """

  import Ecto.Query

  alias Abakus.Categories
  alias Abakus.Depot.BudgetLink.Link
  alias Abakus.Depot.Portfolios.{Account, Portfolio, Transaction}
  alias Abakus.Depot.Valuation
  alias Abakus.{Ledger, Repo}
  alias Abakus.Ledger.Transaction, as: LedgerTransaction
  alias Abakus.Users.{Scope, User}
  alias Ecto.Changeset

  @budget_types [:buy, :sell, :dividend, :cash_transfer]

  @labels %{
    buy: "Kauf",
    sell: "Verkauf",
    cash_transfer: "Umbuchung",
    deposit: "Einlage",
    removal: "Entnahme",
    dividend: "Dividende",
    interest: "Zinsen",
    interest_charge: "Zinsbelastung",
    tax: "Steuern",
    tax_refund: "Steuerrückerstattung",
    fee: "Gebühren",
    fee_refund: "Gebührenerstattung"
  }

  @doc """
  Opens the Ledger accounts of the scope's user's Verrechnungskonten and brings the Ledger transactions their Depot
  transactions lead in line with them, inside the caller's database transaction. Returns `:ok` or
  `{:error, message}`, in German.
  """
  def sync(%Scope{} = scope) do
    with :ok <- open_accounts(scope), do: book(scope)
  end

  defp book(%Scope{user: %User{id: user_id}} = scope) do
    wanted = wanted_by_depot_transaction(context(scope))
    led = Map.new(Repo.all(led_transactions(user_id)), &{&1.depot_transaction_id, &1})

    with :ok <- each(Map.drop(led, Map.keys(wanted)), &remove(scope, &1)) do
      each(Enum.sort(wanted), fn {id, wanted} -> write(scope, id, led[id], wanted) end)
    end
  end

  @doc """
  Removes the Ledger transaction of the scope's user's Depot transaction, inside the caller's database transaction,
  before the Depot transaction is deleted. Returns `:ok` or `{:error, message}`, in German.
  """
  def release(%Scope{user: %User{id: user_id}} = scope, %Transaction{id: id}) do
    led = Repo.all(where(led_transactions(user_id), [t], t.depot_transaction_id == ^id))
    each(Enum.map(led, &{id, &1}), &remove(scope, &1))
  end

  defp led_transactions(user_id),
    do:
      from(t in LedgerTransaction,
        where:
          t.user_id == ^user_id and not is_nil(t.depot_transaction_id) and is_nil(t.deleted_at)
      )

  # A budget account given up by one Verrechnungskonto and taken by another changes hands in this order.
  defp open_accounts(%Scope{user: %User{id: user_id}} = scope) do
    from(a in Account,
      where: a.user_id == ^user_id,
      preload: [:ledger_account, :cash_of_portfolio]
    )
    |> Repo.all()
    |> Enum.sort_by(&(&1.budget_account_id != nil))
    |> each(&open_account(scope, &1))
  end

  defp open_account(_scope, %Account{budget_account_id: id, ledger_account_id: id})
       when id != nil,
       do: :ok

  defp open_account(_scope, %Account{budget_account_id: id} = account) when id != nil,
    do: point(account, id)

  defp open_account(_scope, %Account{ledger_account: %Ledger.Account{kind: :tracking}}), do: :ok

  defp open_account(scope, account) do
    with {:ok, ledger_account} <-
           Ledger.create_account(scope, %{
             name: account.name,
             kind: :tracking,
             closed: closed?(account)
           }) do
      point(account, ledger_account.id)
    end
  end

  defp closed?(%Account{retired: retired, cash_of_portfolio: portfolio}),
    do: retired or match?(%Portfolio{retired: true}, portfolio)

  defp point(account, ledger_account_id) do
    with {:ok, _account} <-
           account |> Changeset.change(ledger_account_id: ledger_account_id) |> Repo.update(),
         do: :ok
  end

  defp context(%Scope{user: %User{id: user_id}} = scope) do
    link = Repo.get(Link, user_id)

    %{
      link: link,
      ready_to_assign_id: link && Categories.ready_to_assign!(scope).id,
      accounts:
        Repo.all(
          from a in Account,
            join: l in assoc(a, :ledger_account),
            where: a.user_id == ^user_id,
            preload: [ledger_account: {l, :transfer_payee}]
        )
        |> Map.new(&{&1.id, &1.ledger_account}),
      portfolios:
        Map.new(Repo.all(from p in Portfolio, where: p.user_id == ^user_id), &{&1.id, &1.name}),
      user_id: user_id
    }
  end

  defp wanted_by_depot_transaction(context) do
    from(t in Transaction,
      where: t.user_id == ^context.user_id and not is_nil(t.account_id),
      preload: :security
    )
    |> Repo.all()
    |> Enum.flat_map(fn transaction ->
      case wanted(transaction, context) do
        nil -> []
        wanted -> [{transaction.id, wanted}]
      end
    end)
    |> Map.new()
  end

  defp wanted(transaction, context) do
    date = NaiveDateTime.to_date(transaction.date_time)

    sides =
      for {account_id, amount} <- Valuation.cash_moved(transaction),
          amount != 0,
          account = context.accounts[account_id],
          written?(context, transaction.type, account, date),
          do: {account_id, account, amount}

    with %{} = wanted <- sides(transaction, sides, context),
         do: Map.merge(wanted, %{date: date, memo: memo(transaction)})
  end

  defp written?(_context, _type, %Ledger.Account{kind: :tracking}, _date), do: true

  defp written?(%{link: %Link{start_date: start}}, type, _account, date),
    do: type in @budget_types and not Date.before?(date, start)

  defp written?(_context, _type, _account, _date), do: false

  defp sides(_transaction, [], _context), do: nil

  defp sides(transaction, [{account_id, account, amount}], context),
    do: side(context, account, amount, nil, payee(transaction, account_id, context))

  defp sides(_transaction, [{_from_id, from, from_amount}, {_to_id, to, to_amount}], context) do
    if Ledger.Account.budget_account?(to) and not Ledger.Account.budget_account?(from),
      do: side(context, to, to_amount, from, {:transfer, from.transfer_payee.id}),
      else: side(context, from, from_amount, to, {:transfer, to.transfer_payee.id})
  end

  defp side(context, account, amount, other, payee) do
    tracking? = not Ledger.Account.budget_account?(account)

    %{
      account_id: account.id,
      amount: amount,
      payee: payee,
      category_id: category_id(context, account, amount, other),
      cleared: if(tracking?, do: :cleared, else: :uncleared),
      approved: tracking?
    }
  end

  defp category_id(context, account, amount, other) do
    cond do
      not Ledger.Account.takes_category?(account, other) -> nil
      amount < 0 -> context.link.category_id
      true -> context.ready_to_assign_id
    end
  end

  defp payee(%Transaction{type: type, portfolio_id: id}, _account_id, context)
       when type in [:buy, :sell],
       do: {:name, context.portfolios[id]}

  defp payee(%Transaction{type: :cash_transfer} = t, account_id, context) do
    other_id = if account_id == t.account_id, do: t.other_account_id, else: t.account_id
    {:name, context.accounts[other_id] && context.accounts[other_id].name}
  end

  defp payee(%Transaction{security: %{name: name}}, _account_id, _context), do: {:name, name}

  defp payee(%Transaction{portfolio_id: id}, _account_id, context),
    do: {:name, context.portfolios[id]}

  defp memo(%Transaction{type: type, security: %{name: name}}), do: "#{@labels[type]} #{name}"
  defp memo(%Transaction{type: type}), do: @labels[type]

  defp remove(scope, {id, led}) do
    with {:ok, _deleted} <- Ledger.delete_transaction(scope, led, opts(id)), do: :ok
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

  defp write(scope, depot_transaction_id, nil, wanted) do
    attrs =
      wanted
      |> Map.take([:account_id, :amount, :date, :memo, :category_id, :cleared, :approved])
      |> Map.merge(payee_attrs(scope, wanted.payee))
      |> Map.put(:source, :depot)

    with {:ok, transaction} <-
           Ledger.create_transaction(scope, attrs,
             led_by: {:depot_transaction, depot_transaction_id}
           ),
         do: settle_counterpart(scope, transaction)
  end

  defp write(scope, depot_transaction_id, led, wanted) do
    attrs =
      wanted
      |> Map.take([:account_id, :amount, :date])
      |> Map.merge(payee_attrs(scope, wanted.payee))
      |> Enum.reject(fn {field, value} -> Map.get(led, field) == value end)
      |> Map.new()
      |> with_category(wanted)

    cond do
      attrs == %{} ->
        :ok

      Map.has_key?(attrs, :payee_id) or Map.has_key?(attrs, :payee_name) ->
        with {:ok, transaction} <- rewrite(scope, led, attrs, depot_transaction_id),
             do: settle_counterpart(scope, transaction)

      true ->
        with {:ok, _transaction} <- rewrite(scope, led, attrs, depot_transaction_id), do: :ok
    end
  end

  # A transaction moved to another account takes the category it would get there.
  defp with_category(%{account_id: _moved} = attrs, wanted),
    do: Map.put(attrs, :category_id, wanted.category_id)

  defp with_category(attrs, _wanted), do: attrs

  defp rewrite(scope, led, attrs, depot_transaction_id),
    do: Ledger.update_transaction(scope, led, attrs, opts(depot_transaction_id))

  # The Ledger writes a new counterpart uncleared; in a tracking account the Depot's booking is all there is.
  defp settle_counterpart(scope, %LedgerTransaction{transfer_transaction_id: id})
       when id != nil do
    counterpart = Repo.preload(Repo.get!(LedgerTransaction, id), :account)

    if counterpart.account.kind == :tracking and
         (counterpart.cleared == :uncleared or not counterpart.approved) do
      attrs = %{cleared: settled(counterpart.cleared), approved: true}
      with {:ok, _counterpart} <- Ledger.update_transaction(scope, counterpart, attrs), do: :ok
    else
      :ok
    end
  end

  defp settle_counterpart(_scope, _transaction), do: :ok

  defp settled(:uncleared), do: :cleared
  defp settled(cleared), do: cleared

  defp payee_attrs(_scope, {:transfer, payee_id}), do: %{payee_id: payee_id}
  defp payee_attrs(_scope, {:name, nil}), do: %{payee_id: nil}

  defp payee_attrs(scope, {:name, name}) do
    case Ledger.find_payee_by_name(scope, name) do
      %{transfer_account_id: nil, id: id} -> %{payee_id: id}
      _none -> %{payee_name: name}
    end
  end

  defp refused(changeset) do
    errors =
      changeset
      |> Changeset.traverse_errors(fn {message, _opts} -> message end)
      |> Enum.flat_map(fn {field, messages} -> Enum.map(messages, &"#{field} #{&1}") end)
      |> Enum.join(", ")

    "Die Buchung in Finanzen ließ sich nicht schreiben (#{errors})."
  end
end
