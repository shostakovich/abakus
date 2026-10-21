defmodule Abakus.Kasse.BudgetLinkTest do
  use Abakus.DataCase

  @moduletag :capture_log

  import Abakus.DomainFixtures
  import Abakus.KasseFixtures

  alias Abakus.{Budget, Categories, Ledger}
  alias Abakus.Categories.Category
  alias Abakus.Kasse.{AccessError, Balances, BudgetLink, Expenses, Recurring}
  alias Abakus.Kasse.BudgetLink.Link
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
      BudgetLink.put_category_mapping(scope_of(h.anna), %{
        h.food => groceries.id,
        kasse_household.id => household_goods.id
      })

    {:ok, _counts} = BudgetLink.switch_on(scope_of(h.anna), account.id)

    %{
      h: h,
      account: account,
      groceries: groceries.id,
      treats: treats.id,
      household_goods: household_goods.id,
      kasse_household: kasse_household.id
    }
  end

  defp kasse_category(name),
    do: Enum.find(KasseCategories.list_categories(Scope.system()), &(&1.name == name))

  defp transaction(expense) do
    Repo.one(
      from t in Transaction,
        where: t.kasse_expense_id == ^expense.id and is_nil(t.deleted_at),
        preload: :payee
    )
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

  defp activity(category_id, month) do
    Categories.budget(budget_scope())
    |> Budget.months(month, month)
    |> Enum.find(&(&1.month == month))
    |> Map.fetch!(:categories)
    |> Enum.find(&(&1.category_id == category_id))
    |> Map.fetch!(:activity)
  end

  describe "scenario: an expense the owner paid" do
    test "books what the others owe her, so the category bears only her share", %{h: h} = c do
      checking = account_fixture(%{name: "Checking", kind: :checking})

      bank =
        transaction_fixture(%{
          account_id: checking.id,
          date: ~D[2026-10-12],
          amount: -2000,
          category_id: c.groceries
        })

      market = create!(equal(h, "Market", 2000, "2026-10-12", h.anna, [h.anna, h.ben]), h.anna)

      assert %{amount: 1000, category_id: groceries} = transaction(market)
      assert groceries == c.groceries
      assert %{amount: -2000, category_id: ^groceries} = Repo.reload!(bank)
      assert activity(c.groceries, ~D[2026-10-01]) == -1000

      assert Ledger.balances(budget_scope())[c.account.id].balance ==
               Balances.balance(scope_of(h.anna))
    end
  end

  describe "scenario: an expense the owner paid entirely for someone else" do
    test "books the whole amount", %{h: h} = c do
      gift = create!(equal(h, "Gift", 1500, "2026-10-12", h.anna, [h.ben]), h.anna)

      assert %{amount: 1500, category_id: groceries} = transaction(gift)
      assert groceries == c.groceries
    end
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

    test "lands in the budget owner's budget with their user, whoever enters it", %{h: h} do
      expense =
        create!(equal(h, "Wocheneinkauf", 8742, "2026-10-12", h.ben, [h.anna, h.ben]), h.ben)

      %{user_id: user_id, payee: payee} = transaction(expense)

      assert user_id == scope_of(h.anna).user.id
      assert payee.user_id == user_id
      assert Ledger.list_transactions(scope_of(h.ben), :all) == []
    end

    test "keeps the account's balance at their Kasse balance, whoever paid", %{h: h} = context do
      create!(equal(h, "Pizza", 3000, "2026-10-10", h.anna, [h.anna, h.ben]))
      create!(equal(h, "Kino", 2400, "2026-10-11", h.ben, [h.anna, h.ben, h.cleo]))

      assert Ledger.balances(budget_scope())[context.account.id].balance == 1500 - 800
      assert Balances.balance(scope_of(h.anna)) == 1500 - 800
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

    test "gives none when it changes nothing for them", %{h: h} = context do
      create!(equal(h, "Bahn", 2000, "2026-10-01", h.ben, [h.ben, h.cleo]))
      create!(equal(h, "Bäcker", 500, "2026-10-01", h.anna, [h.anna]))
      assert live_transactions(context.account) == []
    end

    test "follows a change of the payer", %{h: h} do
      expense = create!(equal(h, "Kino", 2000, "2026-10-10", h.ben, [h.anna, h.ben]))
      first = transaction(expense)

      expense = update!(h.ben, expense, %{paid_by_id: h.anna})
      assert %{amount: 1000, memo: "Gesamt 20,00 € · bezahlt von Anna"} = transaction(expense)

      update!(h.ben, expense, %{parts: [%{participant_id: h.anna, weight: 0}]})
      assert Repo.reload!(first).deleted_at
      assert transaction(expense) == nil
    end
  end

  test "The Kasse leads only on what it changed", %{h: h} = context do
    expense =
      create!(equal(h, "Wocheneinkauf", 8742, "2026-10-12", h.ben, [h.anna, h.ben]), h.ben)

    {:ok, _transaction} =
      Ledger.update_transaction(budget_scope(), transaction(expense), %{
        category_id: context.treats
      })

    expense = update!(h.ben, expense, %{amount_cents: 9000, original_amount: 9000})
    assert %{amount: -4500, category_id: treats} = transaction(expense)
    assert treats == context.treats

    update!(h.ben, expense, %{category_id: context.kasse_household})
    assert transaction(expense).category_id == context.household_goods
  end

  test "a Kasse change keeps a memo the register changed", %{h: h} do
    expense = create!(equal(h, "Markt", 1000, "2026-10-12", h.ben, [h.anna, h.ben]))

    {:ok, _transaction} =
      Ledger.update_transaction(budget_scope(), transaction(expense), %{memo: "Spargel"})

    expense = update!(h.ben, expense, %{amount_cents: 2000, original_amount: 2000})
    assert %{amount: -1000, memo: "Spargel"} = transaction(expense)

    update!(h.ben, expense, %{title: "Wochenmarkt", date: ~D[2026-10-13]})
    assert %{memo: "Spargel", date: ~D[2026-10-13]} = transaction = transaction(expense)
    assert transaction.payee.name == "Wochenmarkt"
  end

  test "a Kasse change writes the memo the register left alone, and keeps cleared state and approval",
       %{h: h} do
    expense = create!(equal(h, "Markt", 1000, "2026-10-12", h.ben, [h.anna, h.ben]))

    {:ok, _transaction} =
      Ledger.update_transaction(budget_scope(), transaction(expense), %{
        cleared: :cleared,
        approved: true
      })

    update!(h.ben, expense, %{amount_cents: 2000, original_amount: 2000})

    assert %{memo: "Gesamt 20,00 € · bezahlt von Ben", cleared: :cleared, approved: true} =
             transaction(expense)
  end

  test "Deleting an expense deletes its transaction", %{h: h} = context do
    expense = create!(equal(h, "Pizza", 3000, "2026-10-10", h.anna, [h.anna, h.ben]))
    transaction = transaction(expense)

    {:ok, _deleted} = Expenses.delete_expense(scope_of(h.ben), expense)

    assert Repo.reload!(transaction).deleted_at
    assert live_transactions(context.account) == []
    refute transaction(expense)
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

  test "the transaction is neither changed nor deleted beside the Kasse", %{h: h} do
    expense = create!(equal(h, "Kino", 2000, "2026-10-10", h.ben, [h.anna, h.ben]))
    linked = transaction(expense)

    assert {:error, _changeset} = Ledger.delete_transaction(budget_scope(), linked)

    assert {:error, changeset} =
             Ledger.update_transaction(budget_scope(), linked, %{amount: -1, payee_name: "X"})

    assert Enum.sort(changeset.errors) == [
             amount: {"folgt der Ausgabe in der Kasse", []},
             payee_id: {"folgt der Ausgabe in der Kasse", []}
           ]

    assert %{amount: -1000, deleted_at: nil} = transaction(expense)
  end

  test "a reconciled transaction follows the Kasse", %{h: h} do
    expense = create!(equal(h, "Kino", 2000, "2026-10-10", h.ben, [h.anna, h.ben]))

    {:ok, _locked} =
      Ledger.update_transaction(budget_scope(), transaction(expense), %{cleared: :reconciled})

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

  describe "the budget owner's scope" do
    test "sees the link, the booking of an expense and the mapping", %{h: h} = context do
      expense = create!(equal(h, "Markt", 1000, "2026-10-12", h.ben, [h.anna, h.ben]))
      owner = scope_of(h.anna)

      assert BudgetLink.account(owner).id == context.account.id
      assert %Transaction{amount: -500} = BudgetLink.transaction_for(owner, expense.id)
      assert BudgetLink.category_mapping(owner)[h.food] == context.groceries
    end

    test "is needed for the booking and the mapping", %{h: h} do
      expense = create!(equal(h, "Markt", 1000, "2026-10-12", h.ben, [h.anna, h.ben]))
      ben = scope_of(h.ben)

      assert BudgetLink.account(ben) == nil
      assert BudgetLink.transaction_for(ben, expense.id) == nil
      assert BudgetLink.transaction_for(Scope.system(), expense.id) == nil
      assert_raise AccessError, fn -> BudgetLink.category_mapping(ben) end
      assert_raise AccessError, fn -> BudgetLink.put_category_mapping(ben, %{h.food => nil}) end
      assert_raise AccessError, fn -> BudgetLink.account_choices(ben) end
      assert BudgetLink.category_mapping(scope_of(h.anna))[h.food]
    end

    test "is the one whose budget the budget's questions are about", %{h: h} = context do
      ben = scope_of(h.ben)

      :ok = BudgetLink.recategorize(ben, context.groceries, context.treats)
      assert BudgetLink.category_mapping(scope_of(h.anna))[h.food] == context.groceries
    end
  end

  describe "the category mapping" do
    test "refuses internal and unknown budget categories", %{h: h} do
      ready_to_assign = Categories.ready_to_assign!(budget_scope())

      assert {:error, _message} =
               BudgetLink.put_category_mapping(scope_of(h.anna), %{
                 "#{h.food}" => "#{ready_to_assign.id}"
               })

      assert {:error, _message} =
               BudgetLink.put_category_mapping(scope_of(h.anna), %{h.food => 999_999})

      assert {:error, _message} =
               BudgetLink.put_category_mapping(scope_of(h.anna), %{999_999 => nil})
    end

    test "clears a mapping with a blank choice", %{h: h} = context do
      assert {:ok, mapping} =
               BudgetLink.put_category_mapping(scope_of(h.anna), %{"#{h.food}" => ""})

      assert mapping == %{context.kasse_household => context.household_goods}
    end

    test "follows a budget category deleted into another", %{h: h} = context do
      expense = create!(equal(h, "Markt", 1000, "2026-10-12", h.ben, [h.anna, h.ben]))
      groceries = Repo.get!(Category, context.groceries)
      treats = Repo.get!(Category, context.treats)

      {:ok, _deleted} = Categories.delete_category(budget_scope(), groceries, treats)

      assert BudgetLink.category_mapping(scope_of(h.anna))[h.food] == context.treats

      expense = update!(h.ben, expense, %{amount_cents: 2000, original_amount: 2000})
      assert %{amount: -1000, category_id: treats_id} = transaction(expense)
      assert treats_id == context.treats
    end
  end
end
