defmodule Abakus.Kasse.BudgetLinkPropertyTest do
  use Abakus.DataCase
  use ExUnitProperties

  import Abakus.DomainFixtures
  import Abakus.KasseFixtures

  alias Abakus.Kasse
  alias Abakus.Kasse.{Balances, BudgetLink, Expenses}
  alias Abakus.Kasse.BudgetLink.Link
  alias Abakus.Kasse.Expenses.Expense
  alias Abakus.Ledger
  alias Abakus.Ledger.Transaction

  @first ~D[2026-10-01]
  @start ~D[2026-10-15]

  setup do
    h = household()
    shared = account_fixture(%{name: "Shared", kind: :cash})
    checking = account_fixture(%{name: "Checking", kind: :checking})
    food = category_fixture(%{name: "Food"})
    {:ok, _mapping} = BudgetLink.put_category_mapping(scope_of(h.anna), %{h.food => food.id})
    {:ok, _created} = BudgetLink.switch_on(scope_of(h.anna), shared.id)

    %{h: h, shared: shared, checking: checking, food: food.id}
  end

  defp day(from \\ @first),
    do: map(integer(0..Date.diff(~D[2026-11-10], from)), &Date.add(from, &1))

  defp cents, do: integer(1..50_000)

  defp step(people, start) do
    others = Enum.drop(people, 1)
    groups = for picks <- subsets(people), picks != [], do: picks
    pairs = for a <- people, b <- people, a != b, do: [a, b]

    expense =
      gen all(
            payer <- member_of(people),
            parts <- member_of(groups),
            weights <- list_of(integer(1..3), length: length(parts)),
            cents <- cents(),
            date <- day()
          ) do
        {payer, Enum.zip(parts, weights), cents, date}
      end

    # Edited, an expense without a transaction gets one only when dated from the start date on.
    edit =
      gen all(
            {payer, parts, cents, _date} <- expense,
            date <- day(start || @first)
          ) do
        {payer, parts, cents, date}
      end

    one_of([
      map(expense, &{:expense, &1}),
      gen all(index <- integer(0..7), actor <- member_of(people), edit <- edit) do
        {:edit, index, actor, edit}
      end,
      map(integer(0..7), &{:delete, &1}),
      gen all(
            [payer, recipient] <- member_of(pairs),
            cents <- cents(),
            date <- day(),
            account <- member_of([:checking, nil])
          ) do
        {:reimbursement, payer, recipient, cents, date, account}
      end,
      gen all(index <- integer(0..7), account <- member_of([:checking, nil])) do
        {:account, index, account}
      end,
      gen all(index <- integer(0..7), offset <- integer(-3..3)) do
        {:complete, index, offset}
      end,
      gen all(
            person <- member_of(others),
            cents <- one_of([integer(-50_000..-1), cents()]),
            date <- day()
          ) do
        {:transfer, person, cents, date}
      end
    ])
  end

  defp subsets([]), do: [[]]
  defp subsets([first | rest]), do: Enum.flat_map(subsets(rest), &[&1, [first | &1]])

  # `outside` is what register transfers dated before the start date moved in Shared without the Kasse.
  defp run(c, {:expense, {payer, parts, cents, date}}, state) do
    expense = create!(expense_attrs(c, payer, parts, cents, date), payer)
    purchase(c, put_in(state.expenses[expense.id], expense), expense)
  end

  defp run(c, {:edit, index, actor, {payer, parts, cents, date}}, state) do
    case pick(state.expenses, index) do
      nil ->
        state

      expense ->
        {:ok, expense} =
          Expenses.update_expense(
            scope_of(actor),
            expense,
            expense_attrs(c, payer, parts, cents, date)
          )

        purchase(c, put_in(state.expenses[expense.id], expense), expense)
    end
  end

  defp run(_c, {:delete, index}, state) do
    case pick(Map.merge(state.expenses, state.reimbursements), index) do
      nil ->
        state

      expense ->
        {:ok, _deleted} = Expenses.delete_expense(scope_of(expense.paid_by_id), expense)

        state
        |> Map.update!(:expenses, &Map.delete(&1, expense.id))
        |> Map.update!(:reimbursements, &Map.delete(&1, expense.id))
        |> unpurchase(expense.id)
    end
  end

  defp run(c, {:reimbursement, payer, recipient, cents, date, account}, state) do
    attrs = reimbursement(cents, Date.to_iso8601(date), payer, recipient)

    {:ok, payback} =
      if c.h.anna in [payer, recipient],
        do:
          Expenses.create_expense(scope_of(c.h.anna), attrs,
            budget_account_id: account_id(c, account)
          ),
        else: Expenses.create_expense(scope_of(payer), attrs)

    put_in(state.reimbursements[payback.id], payback)
  end

  defp run(c, {:account, index, account}, state) do
    case pick(owners(c, state), index) do
      nil ->
        state

      payback ->
        {:ok, _payback} =
          Expenses.update_expense(scope_of(c.h.anna), payback, Expenses.input(payback),
            budget_account_id: account_id(c, account)
          )

        state
    end
  end

  defp run(c, {:complete, index, offset}, state) do
    open =
      c
      |> owners(state)
      |> Map.values()
      |> Enum.map(&BudgetLink.transaction_for(scope_of(c.h.anna), &1.id))
      |> Enum.filter(&(&1 && is_nil(&1.transfer_transaction_id)))

    case pick(open, index) do
      nil ->
        state

      transaction ->
        payback = Repo.preload(Repo.get!(Expense, transaction.kasse_expense_id), :shares)
        [%{participant_id: recipient}] = payback.shares
        other = if payback.paid_by_id == c.h.anna, do: recipient, else: payback.paid_by_id
        transfer(c, state, other, -transaction.amount, Date.add(transaction.date, offset))
    end
  end

  defp run(c, {:transfer, person, cents, date}, state),
    do: transfer(c, state, person, cents, date)

  defp transfer(c, state, person, cents, date) do
    {:ok, _transfer} =
      BudgetLink.write_from_register(
        budget_scope(),
        nil,
        %{
          account_id: c.checking.id,
          date: date,
          amount: cents,
          payee_id: c.shared.transfer_payee.id
        },
        person_id: person
      )

    reimbursements =
      Repo.all(
        from e in Expense,
          where: e.reimbursement and is_nil(e.deleted_at),
          preload: [:shares]
      )

    state = %{state | reimbursements: Map.new(reimbursements, &{&1.id, &1})}

    if state.start && Date.before?(date, state.start),
      do: Map.update!(state, :outside, &(&1 - cents)),
      else: state
  end

  defp expense_attrs(c, payer, parts, cents, date) do
    %{
      title: "Market",
      date: date,
      category_id: c.h.food,
      paid_by_id: payer,
      amount_cents: cents,
      split_mode: :shares,
      parts: Enum.map(parts, fn {id, weight} -> %{participant_id: id, weight: weight} end)
    }
  end

  defp pick(items, index) when is_map(items),
    do: items |> Enum.sort() |> Enum.map(&elem(&1, 1)) |> pick(index)

  defp pick([], _index), do: nil
  defp pick(items, index), do: Enum.at(items, rem(index, length(items)))

  defp owners(c, state) do
    state.reimbursements
    |> Map.new(fn {id, payback} -> {id, Repo.preload(payback, :shares, force: true)} end)
    |> Map.filter(fn {_id, payback} ->
      payback.paid_by_id == c.h.anna or Expense.share_of(payback, c.h.anna) != 0
    end)
  end

  defp account_id(c, :checking), do: c.checking.id
  defp account_id(_c, nil), do: nil

  defp purchase(c, state, %Expense{paid_by_id: anna} = expense) when anna == c.h.anna do
    attrs = %{account_id: c.checking.id, date: expense.date, amount: -expense.amount_cents}

    bought =
      case state.purchases[expense.id] do
        nil ->
          transaction_fixture(Map.put(attrs, :category_id, c.food))

        bought ->
          {:ok, bought} = Ledger.update_transaction(budget_scope(), bought, attrs)
          bought
      end

    put_in(state.purchases[expense.id], bought)
  end

  defp purchase(_c, state, expense), do: unpurchase(state, expense.id)

  defp unpurchase(state, expense_id) do
    case Map.pop(state.purchases, expense_id) do
      {nil, _purchases} ->
        state

      {bought, purchases} ->
        {:ok, _deleted} = Ledger.delete_transaction(budget_scope(), bought)
        %{state | purchases: purchases}
    end
  end

  defp owner_shares(anna) do
    from(e in Expense, where: is_nil(e.deleted_at) and not e.reimbursement, preload: :shares)
    |> Repo.all()
    |> Enum.map(&Expense.share_of(&1, anna))
    |> Enum.sum()
  end

  # What reimbursements without an account change in the owner's Kasse balance, uncategorised in that account.
  defp open_reimbursements(c) do
    from(e in Expense,
      where: e.reimbursement and is_nil(e.deleted_at),
      preload: [:paid_by, :shares]
    )
    |> Repo.all()
    |> Enum.filter(fn payback ->
      linked = BudgetLink.transaction_for(scope_of(c.h.anna), payback.id)
      linked && is_nil(linked.transfer_transaction_id)
    end)
    |> Enum.map(&Kasse.Ledger.change(&1, c.h.anna))
    |> Enum.sum()
  end

  defp activity(by_key, category_id) do
    by_key
    |> Enum.filter(fn {{id, _month}, _amount} -> id == category_id end)
    |> Enum.map(&elem(&1, 1))
    |> Enum.sum()
  end

  defp led_once?(c) do
    led =
      Repo.all(
        from t in Transaction,
          where: not is_nil(t.kasse_expense_id) and is_nil(t.deleted_at),
          select: t.kasse_expense_id
      )

    changing =
      from(e in Expense, where: is_nil(e.deleted_at), preload: :shares)
      |> Repo.all()
      |> Enum.filter(&(Kasse.Ledger.change(&1, c.h.anna) != 0))
      |> Enum.map(& &1.id)

    Enum.sort(led) == Enum.sort(changing)
  end

  property "the shared-expenses account shows the owner's balance, categories their shares", c do
    people = [c.h.anna, c.h.ben, c.h.cleo]

    check all(
            start <- member_of([nil, @start]),
            steps <- list_of(step(people, start), max_length: 10)
          ) do
      Repo.transaction(fn ->
        Repo.update!(Ecto.Changeset.change(Repo.get!(Link, c.h.anna), start_date: start))
        state = %{start: start, expenses: %{}, reimbursements: %{}, purchases: %{}, outside: 0}
        state = Enum.reduce(steps, state, &run(c, &1, &2))

        balance = Map.get(Ledger.balances(budget_scope()), c.shared.id, %{balance: 0}).balance
        assert balance == Balances.balance(scope_of(c.h.anna)) + state.outside

        by_key = Ledger.budget_activity(budget_scope())
        assert activity(by_key, c.food) == -owner_shares(c.h.anna)
        assert activity(by_key, nil) == open_reimbursements(c)
        assert led_once?(c)

        Repo.rollback(:checked)
      end)
    end
  end
end
