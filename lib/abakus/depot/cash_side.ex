defmodule Abakus.Depot.CashSide do
  @moduledoc """
  The money of the Depot in the Ledger (ADR 0020). Each Depot transaction's cash side is a Ledger transaction it
  leads in the account it names, written with the user's scope; a cash transfer between two accounts is a Ledger
  transfer, led from its budget side if it has one.

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
  alias Abakus.Depot.Portfolios.{Portfolio, Transaction}
  alias Abakus.Depot.Valuation
  alias Abakus.{Ledger, Repo}
  alias Abakus.Ledger.Transaction, as: LedgerTransaction
  alias Abakus.Users.{Scope, User}
  alias Ecto.Changeset

  @budget_types [:buy, :sell, :dividend, :cash_transfer]

  @doc """
  Brings the Ledger transactions the scope's user's Depot transactions lead in line with them, inside the caller's
  database transaction. Returns `:ok` or `{:error, message}`, in German.
  """
  def sync(%Scope{user: %User{id: user_id}} = scope) do
    context = context(scope)
    wanted = wanted_by_depot_transaction(context)
    led = Map.new(Repo.all(led_transactions(user_id)), &{&1.depot_transaction_id, &1})

    with :ok <- each(Map.drop(led, Map.keys(wanted)), &remove(scope, &1)) do
      each(Enum.sort(wanted), fn {id, wanted} ->
        write(scope, id, led[id], wanted, context.accounts)
      end)
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

  defp context(%Scope{user: %User{id: user_id}} = scope) do
    link = Repo.get(Link, user_id)

    %{
      link: link,
      ready_to_assign_id: link && Categories.ready_to_assign!(scope).id,
      accounts: Map.new(Ledger.list_accounts(scope), &{&1.id, &1}),
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

  defp memo(%Transaction{type: type, security: %{name: name}}),
    do: "#{Transaction.label(type)} #{name}"

  defp memo(%Transaction{type: type}), do: Transaction.label(type)

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

  defp write(scope, depot_transaction_id, nil, wanted, _accounts) do
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

  defp write(scope, depot_transaction_id, led, wanted, accounts) do
    attrs =
      wanted
      |> Map.take([:account_id, :amount, :date])
      |> Map.merge(payee_attrs(scope, wanted.payee))
      |> Enum.reject(fn {field, value} -> Map.get(led, field) == value end)
      |> Map.new()
      |> with_category(led, wanted)
      |> with_state(led, wanted, accounts)

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

  # Moved to another account or turned from outflow to inflow, it takes the category it would get anew.
  defp with_category(attrs, led, wanted) do
    if Map.has_key?(attrs, :account_id) or led.amount < 0 != wanted.amount < 0,
      do: Map.put(attrs, :category_id, wanted.category_id),
      else: attrs
  end

  defp with_state(%{account_id: id} = attrs, led, wanted, accounts) do
    if Ledger.Account.budget_account?(accounts[id]) ==
         Ledger.Account.budget_account?(accounts[led.account_id]),
       do: attrs,
       else: Map.merge(attrs, Map.take(wanted, [:cleared, :approved]))
  end

  defp with_state(attrs, _led, _wanted, _accounts), do: attrs

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
      {:ok, %{transfer_account_id: nil, id: id}} -> %{payee_id: id}
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
