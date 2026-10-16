defmodule Abakus.Kasse.BudgetLinkTest do
  use Abakus.DataCase

  @moduletag :capture_log

  import Abakus.DomainFixtures
  import Abakus.KasseFixtures

  alias Abakus.{Categories, Ledger}
  alias Abakus.Categories.Category
  alias Abakus.Kasse.{Balances, BudgetLink, Expenses, Participants, Recurring}
  alias Abakus.Kasse.BudgetLink.{Link, LinkedTransaction}
  alias Abakus.Kasse.Categories, as: KasseCategories
  alias Abakus.Kasse.Expenses.Expense
  alias Abakus.Ledger.Transaction
  alias Abakus.MCP.Tools
  alias Abakus.Users.Scope

  setup do
    h = household()
    account = account_fixture(%{name: "Geteilt", kind: :cash, fed_by: :shared_expenses})
    group = category_group_fixture(%{name: "🏠 Alltag"})
    groceries = category_fixture(%{name: "🛒 Lebensmittel", category_group_id: group.id})
    treats = category_fixture(%{name: "🍷 Genuss", category_group_id: group.id})
    household_goods = category_fixture(%{name: "🧽 Haushalt", category_group_id: group.id})
    kasse_household = kasse_category("Haushalt")

    {:ok, _mapping} =
      BudgetLink.put_category_mapping(%{
        h.food => groceries.id,
        kasse_household.id => household_goods.id
      })

    {:ok, _counts} = BudgetLink.switch_on(Participants.get_participant!(h.anna), account.id)

    %{
      h: h,
      account: account,
      groceries: groceries.id,
      treats: treats.id,
      household_goods: household_goods.id,
      kasse_household: kasse_household.id
    }
  end

  defp kasse_category(name), do: Enum.find(KasseCategories.list_categories(), &(&1.name == name))

  defp transaction(expense) do
    case Repo.get_by(LinkedTransaction, expense_id: expense.id) do
      nil -> nil
      link -> Repo.preload(Repo.get!(Transaction, link.transaction_id), :payee)
    end
  end

  defp live_transactions(account),
    do:
      Repo.all(from t in Transaction, where: t.account_id == ^account.id and is_nil(t.deleted_at))

  defp update!(actor, expense, changes) do
    {:ok, expense} =
      Expenses.update_expense(
        scope_of(actor),
        expense,
        Map.merge(Expenses.input(expense), changes)
      )

    expense
  end

  describe "an expense of a linked participant" do
    test "books their share in the shared-expenses account, unapproved", %{h: h} = context do
      expense =
        create!(equal(h, "Wocheneinkauf", 8742, "2026-10-12", h.ben, [h.anna, h.ben]), h.ben)

      transaction = transaction(expense)

      assert %{
               account_id: account_id,
               amount: -4371,
               date: ~D[2026-10-12],
               category_id: category_id,
               memo: "Gesamt 87,42 € · bezahlt von Ben",
               approved: false,
               cleared: :cleared,
               source: :kasse
             } = transaction

      assert {account_id, category_id} == {context.account.id, context.groceries}
      assert transaction.payee.name == "Wocheneinkauf"
    end

    test "keeps the account's balance at minus the shares, whoever paid", %{h: h} = context do
      create!(equal(h, "Pizza", 3000, "2026-10-10", h.anna, [h.anna, h.ben]))
      create!(equal(h, "Kino", 2400, "2026-10-11", h.ben, [h.anna, h.ben, h.cleo]))

      assert Ledger.balances()[context.account.id].balance == -2300
      assert Balances.balance(scope_of(h.anna)) == 3000 - 2300
    end

    test "names the foreign amount in the memo", %{h: h} do
      expense =
        create!(foreign(h, "Hotel", 10_000, "USD", 1.25, "2026-10-01", h.anna, [h.anna, h.ben]))

      assert transaction(expense).memo ==
               "Gesamt 80,00 € (100,00 USD) · bezahlt von Anna"
    end

    test "has no category in the budget when its Kasse category is not mapped", %{h: h} do
      expense =
        h
        |> equal("Essen", 2000, "2026-10-01", h.anna, [h.anna, h.ben])
        |> Map.put(:category_id, h.restaurant)
        |> create!()

      assert transaction(expense).category_id == nil
    end

    test "gives none without a share of theirs", %{h: h} = context do
      create!(equal(h, "Bahn", 2000, "2026-10-01", h.ben, [h.ben, h.cleo]))
      assert live_transactions(context.account) == []
    end
  end

  test "The Kasse leads only on what it changed", %{h: h} = context do
    expense =
      create!(equal(h, "Wocheneinkauf", 8742, "2026-10-12", h.ben, [h.anna, h.ben]), h.ben)

    {:ok, _transaction} =
      Ledger.update_transaction(transaction(expense), %{category_id: context.treats})

    expense = update!(h.ben, expense, %{amount_cents: 9000, original_amount: 9000})
    assert %{amount: -4500, category_id: treats} = transaction(expense)
    assert treats == context.treats

    update!(h.ben, expense, %{category_id: context.kasse_household})
    assert transaction(expense).category_id == context.household_goods
  end

  test "a Kasse change keeps a memo the register changed", %{h: h} do
    expense = create!(equal(h, "Markt", 1000, "2026-10-12", h.ben, [h.anna, h.ben]))
    {:ok, _transaction} = Ledger.update_transaction(transaction(expense), %{memo: "Spargel"})

    expense = update!(h.ben, expense, %{amount_cents: 2000, original_amount: 2000})
    assert %{amount: -1000, memo: "Spargel"} = transaction(expense)

    update!(h.ben, expense, %{title: "Wochenmarkt", date: ~D[2026-10-13]})
    assert %{memo: "Spargel", date: ~D[2026-10-13]} = transaction = transaction(expense)
    assert transaction.payee.name == "Wochenmarkt"
  end

  test "a Kasse change writes the memo the register left alone, and keeps flag and approval",
       %{h: h} do
    expense = create!(equal(h, "Markt", 1000, "2026-10-12", h.ben, [h.anna, h.ben]))

    {:ok, _transaction} =
      Ledger.update_transaction(transaction(expense), %{flag: :red, approved: true})

    update!(h.ben, expense, %{amount_cents: 2000, original_amount: 2000})

    assert %{memo: "Gesamt 20,00 € · bezahlt von Ben", flag: :red, approved: true} =
             transaction(expense)
  end

  test "Deleting an expense deletes its transaction", %{h: h} = context do
    expense = create!(equal(h, "Pizza", 3000, "2026-10-10", h.anna, [h.anna, h.ben]))
    transaction = transaction(expense)

    {:ok, _deleted} = Expenses.delete_expense(scope_of(h.ben), expense)

    assert Repo.reload!(transaction).deleted_at
    assert live_transactions(context.account) == []
    refute Repo.get_by(LinkedTransaction, expense_id: expense.id)
  end

  test "A reimbursement gives no transaction", %{h: h} = context do
    create!(reimbursement(8437, "2026-10-10", h.anna, h.ben), h.anna)
    assert live_transactions(context.account) == []
  end

  test "a share that goes away takes the transaction along, and a new one books anew", %{h: h} do
    expense = create!(equal(h, "Kino", 2000, "2026-10-10", h.ben, [h.anna, h.ben]))
    first = transaction(expense)

    expense =
      update!(h.ben, expense, %{parts: [%{participant_id: h.ben, weight: 0}]})

    assert Repo.reload!(first).deleted_at
    assert transaction(expense) == nil

    update!(h.ben, expense, %{
      parts: [%{participant_id: h.anna, weight: 0}, %{participant_id: h.ben, weight: 0}]
    })

    assert %{amount: -1000, deleted_at: nil} = transaction(expense)
  end

  test "a transaction deleted beside the Kasse is booked anew on the next change", %{h: h} do
    expense = create!(equal(h, "Kino", 2000, "2026-10-10", h.ben, [h.anna, h.ben]))
    {:ok, _deleted} = Ledger.delete_transaction(transaction(expense))

    update!(h.ben, expense, %{title: "Kino am Abend"})
    assert %{amount: -1000, deleted_at: nil} = transaction(expense)
  end

  test "a reconciled transaction follows the Kasse", %{h: h} do
    expense = create!(equal(h, "Kino", 2000, "2026-10-10", h.ben, [h.anna, h.ben]))
    {:ok, _locked} = Ledger.update_transaction(transaction(expense), %{cleared: :reconciled})

    update!(h.ben, expense, %{amount_cents: 3000, original_amount: 3000})
    assert transaction(expense).amount == -1500
  end

  test "Recurring rent creates its expense and the linked transaction in one run", %{h: h} do
    rent =
      h
      |> equal("Miete", 120_000, "2026-08-01", h.ben, [h.anna, h.ben])
      |> create!()

    {:ok, rule, _created} =
      Recurring.create_rule(Scope.system(), rent, :monthly, today: ~D[2026-08-01])

    assert Recurring.catch_up(Scope.system(), today: ~D[2026-09-01]) == {:ok, 1}

    occurrence =
      Repo.get_by!(Expense,
        recurring_expense_id: rule.id,
        date: ~D[2026-09-01]
      )

    assert %{amount: -60_000, date: ~D[2026-09-01]} = transaction(occurrence)
  end

  test "MCP create_expense creates the linked transaction", context do
    {text, false} =
      Tools.call(
        "create_expense",
        %{
          "title" => "Rewe",
          "amount" => "30",
          "paid_by" => "Ben",
          "date" => "2026-10-12",
          "category" => "Lebensmittel",
          "participants" => ["Anna", "Ben", "Cleo"]
        },
        today: ~D[2026-10-15]
      )

    id = JSON.decode!(text)["created"]["id"]

    assert %{amount: -1000, category_id: groceries} =
             transaction(Expenses.get_expense!(Scope.system(), id))

    assert groceries == context.groceries
  end

  describe "unlinked" do
    test "nothing is booked for a participant who is not linked", %{h: h} = context do
      Repo.delete_all(Link)

      create!(equal(h, "Pizza", 3000, "2026-10-10", h.anna, [h.anna, h.ben]))
      assert live_transactions(context.account) == []
    end
  end

  describe "the category mapping" do
    test "refuses internal and unknown budget categories", %{h: h} do
      ready_to_assign = Categories.ready_to_assign!()

      assert {:error, _message} =
               BudgetLink.put_category_mapping(%{"#{h.food}" => "#{ready_to_assign.id}"})

      assert {:error, _message} = BudgetLink.put_category_mapping(%{h.food => 999_999})
      assert {:error, _message} = BudgetLink.put_category_mapping(%{999_999 => nil})
    end

    test "clears a mapping with a blank choice", %{h: h} = context do
      assert {:ok, mapping} = BudgetLink.put_category_mapping(%{"#{h.food}" => ""})
      assert mapping == %{context.kasse_household => context.household_goods}
    end

    test "follows a budget category deleted into another", %{h: h} = context do
      expense = create!(equal(h, "Markt", 1000, "2026-10-12", h.ben, [h.anna, h.ben]))
      groceries = Repo.get!(Category, context.groceries)
      treats = Repo.get!(Category, context.treats)

      {:ok, _deleted} = Categories.delete_category(groceries, treats)

      assert BudgetLink.category_mapping()[h.food] == context.treats

      expense = update!(h.ben, expense, %{amount_cents: 2000, original_amount: 2000})
      assert %{amount: -1000, category_id: treats_id} = transaction(expense)
      assert treats_id == context.treats
    end
  end
end
