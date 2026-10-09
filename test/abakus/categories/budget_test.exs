defmodule Abakus.Categories.BudgetTest do
  use Abakus.DataCase

  import Abakus.DomainFixtures

  alias Abakus.{Budget, Categories, Ledger}
  alias Abakus.Budget.Month

  @october ~D[2026-10-01]
  @november ~D[2026-11-01]

  setup do
    %{checking: account_fixture(kind: :checking), rta: Categories.ready_to_assign!()}
  end

  defp month(month, current \\ @october) do
    Categories.budget() |> Budget.months(current, month) |> Enum.find(&(&1.month == month))
  end

  defp row(%Month{categories: rows}, %{id: id}), do: Enum.find(rows, &(&1.category_id == id))

  defp budget_balance do
    Repo.one(
      from t in Ledger.in_register(),
        join: a in assoc(t, :account),
        where: a.kind != :tracking,
        select: sum(t.amount)
    )
  end

  defp income(account, rta, amount, date \\ ~D[2026-10-01]),
    do:
      transaction_fixture(account_id: account.id, category_id: rta.id, amount: amount, date: date)

  describe "scenario: overspending leaves the next month uncovered" do
    test "October shows 100 € and warns that November is 300 € short", c do
      groceries = category_fixture(name: "Lebensmittel")
      rent = category_fixture(name: "Miete")
      income(c.checking, c.rta, 100_000)
      Categories.assign(groceries, @october, 40_000)
      transaction_fixture(account_id: c.checking.id, category_id: groceries.id, amount: -80_000)
      Categories.assign(rent, @november, 50_000)

      october = month(@october)

      assert october.ready_to_assign_shown == 10_000
      assert october.uncovered == [{@november, 30_000}]
    end
  end

  describe "scenario: filling underfunded stops where Ready to Assign ends" do
    test "Strom gets 40 € and Internet 10 €", c do
      group = category_group_fixture()
      power = category_fixture(name: "Strom", category_group_id: group.id, position: 0)
      internet = category_fixture(name: "Internet", category_group_id: group.id, position: 1)
      Categories.set_target(power, %{from_month: @october, cadence: :monthly, amount: 4_000})
      Categories.set_target(internet, %{from_month: @october, cadence: :monthly, amount: 3_000})
      income(c.checking, c.rta, 5_000)

      assert {:ok, [{power.id, 4_000}, {internet.id, 1_000}]} ==
               Categories.fill_underfunded(@october, @october)

      october = month(@october)
      assert row(october, power).assigned == 4_000
      assert row(october, internet).assigned == 1_000
      assert october.ready_to_assign_shown == 0
    end
  end

  describe "budget/0" do
    test "the budget accounts' balance is Ready to Assign plus what is available", c do
      groceries = category_fixture()
      household = category_fixture()
      savings = account_fixture(kind: :savings)
      depot = account_fixture(kind: :tracking)
      split = &transaction_fixture(account_id: c.checking.id, amount: &1, subtransactions: &2)
      income(c.checking, c.rta, 300_000)

      split.(-3_000, [
        %{amount: -2_000, payee_id: savings.transfer_payee.id},
        %{amount: -1_000, category_id: groceries.id}
      ])

      split.(-1_500, [
        %{amount: -500, payee_id: depot.transfer_payee.id, category_id: household.id},
        %{amount: -1_000}
      ])

      split.(9_000, [
        %{amount: 10_000, category_id: c.rta.id},
        %{amount: -1_000, category_id: groceries.id}
      ])

      {:ok, _} = Ledger.delete_transaction(split.(-700, [%{amount: -300}, %{amount: -400}]))

      transaction_fixture(
        account_id: depot.id,
        payee_id: c.checking.transfer_payee.id,
        counterpart_category_id: household.id,
        amount: -4_000
      )

      Categories.assign(groceries, @october, 5_000)
      october = month(@october)

      assert october.income == 310_000
      assert row(october, groceries).activity == -2_000
      assert row(october, household).activity == 3_500
      assert october.uncategorised.activity == -1_000
      assert budget_balance() == october.ready_to_assign + october.available
    end

    test "counts splits by their parts and transfers to tracking accounts by their category", c do
      groceries = category_fixture()
      household = category_fixture()
      depot = account_fixture(kind: :tracking)

      transaction_fixture(
        account_id: c.checking.id,
        amount: -3_000,
        subtransactions: [
          %{amount: -2_000, category_id: groceries.id},
          %{amount: -1_000, category_id: household.id}
        ]
      )

      transaction_fixture(
        account_id: c.checking.id,
        payee_id: depot.transfer_payee.id,
        category_id: household.id,
        amount: -5_000
      )

      october = month(@october)

      assert row(october, groceries).activity == -2_000
      assert row(october, household).activity == -6_000
      assert october.uncategorised.activity == 0
    end

    test "leaves out transfers between budget accounts, tracking accounts, deleted ones and proposals",
         c do
      groceries = category_fixture()
      savings = account_fixture(kind: :savings)
      depot = account_fixture(kind: :tracking)

      transaction_fixture(account_id: c.checking.id, payee_id: savings.transfer_payee.id)
      transaction_fixture(account_id: depot.id, amount: 100_000)
      deleted = transaction_fixture(account_id: c.checking.id, category_id: groceries.id)
      {:ok, _} = Ledger.delete_transaction(deleted)
      manual = transaction_fixture(account_id: c.checking.id, category_id: groceries.id)

      transaction_fixture(
        account_id: c.checking.id,
        amount: manual.amount,
        source: :file,
        matched_transaction_id: manual.id
      )

      october = month(@october)

      assert row(october, groceries).activity == manual.amount
      assert october.uncategorised.activity == 0
      assert october.income == 0
    end

    test "puts transactions without a category on their own row, also in a split", c do
      groceries = category_fixture()
      transaction_fixture(account_id: c.checking.id, amount: -700)

      transaction_fixture(
        account_id: c.checking.id,
        amount: -3_000,
        subtransactions: [%{amount: -2_000, category_id: groceries.id}, %{amount: -1_000}]
      )

      assert month(@october).uncategorised.activity == -1_700
    end

    test "counts income in the month it is dated", c do
      income(c.checking, c.rta, 250_000, ~D[2026-11-30])

      assert month(@october).income == 0
      assert month(@november).income == 250_000
    end

    test "lists every category in budget order, hidden ones included" do
      second = category_group_fixture(position: 1)
      first = category_group_fixture(position: 0)
      b = category_fixture(category_group_id: first.id, position: 1)
      a = category_fixture(category_group_id: first.id, position: 0, hidden: true)
      c = category_fixture(category_group_id: second.id, position: 0)
      Categories.update_category_group(second, %{hidden: true})

      assert Categories.budget().categories == [
               %{id: a.id, hidden: true},
               %{id: b.id, hidden: false},
               %{id: c.id, hidden: true}
             ]
    end
  end

  describe "fill_underfunded/2" do
    test "takes any day of the months, as a date or ISO 8601 string", c do
      category = category_fixture()
      Categories.set_target(category, %{from_month: @october, cadence: :monthly, amount: 4_000})
      income(c.checking, c.rta, 5_000)

      assert {:ok, [{category.id, 4_000}]} ==
               Categories.fill_underfunded("2026-10-15", ~D[2026-10-09])
    end

    test "skips hidden categories and returns nothing when nothing is to assign", c do
      hidden = category_fixture(hidden: true)
      Categories.set_target(hidden, %{from_month: @october, cadence: :monthly, amount: 4_000})
      income(c.checking, c.rta, 5_000)

      assert {:ok, []} = Categories.fill_underfunded(@october, @october)
      assert row(month(@october), hidden).assigned == 0
    end
  end
end
