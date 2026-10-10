defmodule Abakus.YnabImportTest do
  use Abakus.DataCase

  import Abakus.DomainFixtures

  alias Abakus.{Categories, FakeYnab, Ledger, YnabImport}
  alias Abakus.Categories.{Assignment, Category, CategoryGroup, TargetSnooze, TargetVersion}
  alias Abakus.Ledger.{Account, BankBalance, Payee, Transaction}
  alias Abakus.YnabImport.Report

  @fixture Path.expand("../fixtures/ynab/plan.json", __DIR__)
  @external_resource @fixture
  @plan @fixture |> File.read!() |> JSON.decode!() |> Map.fetch!("plan")

  @test_plan Path.expand("../fixtures/ynab/test_plan.json", __DIR__)
  @external_resource @test_plan

  describe "import_plan/1" do
    test "matches the numbers of YNAB's own export of a test plan" do
      plan = @test_plan |> File.read!() |> JSON.decode!() |> Map.fetch!("plan")

      assert {:ok, %Report{differences: [], merged_payees: [{"REWE", ["Rewe"]}]}} =
               YnabImport.import_plan(plan)

      assert [giro, depot, tagesgeld] = Ledger.list_accounts()
      assert giro.last_reconciled_at == ~U[2026-10-09 17:09:56.000000Z]
      assert {depot.kind, tagesgeld.closed} == {:tracking, true}

      assert Repo.exists?(
               from t in Transaction, where: t.account_id == ^giro.id and t.cleared == :reconciled
             )

      # Entertainment's snoozed October is still underfunded, in YNAB as in Abakus.
      assert Categories.target_snoozed?(category("🍿 Entertainment"), ~D[2026-10-01])
      assert Categories.target_snoozed?(category("🛒 Groceries"), ~D[2026-10-01])
      refute Categories.target_snoozed?(category("🛒 Groceries"), ~D[2026-11-01])
      assert category("🚘 Transportation").hidden
    end

    test "loads the plan, and every month, category and account matches YNAB" do
      assert {:ok, %Report{} = report} = YnabImport.import_plan(@plan)

      assert report.differences == []
      assert report.plan == "Testhaushalt"
      assert report.counts == %{accounts: 4, categories: 7, payees: 5, transactions: 18}
      assert report.merged_payees == [{"REWE", ["Rewe"]}]
    end

    test "maps accounts, groups and categories in YNAB's order" do
      {:ok, _report} = YnabImport.import_plan(@plan)

      assert [giro, tagesgeld, depot, bargeld] = Ledger.list_accounts()
      assert {giro.name, giro.kind, giro.position} == {"💳 Girokonto", :checking, 0}
      assert giro.last_reconciled_at == ~U[2026-08-31 18:00:00.000000Z]

      plan =
        put_in(@plan, ["accounts", Access.at(0), "last_reconciled_at"], "2026-08-31T18:00:00.000")

      {:ok, _report} = YnabImport.import_plan(plan)
      assert hd(Ledger.list_accounts()).last_reconciled_at == ~U[2026-08-31 18:00:00.000000Z]
      assert {tagesgeld.kind, tagesgeld.closed} == {:savings, false}
      assert {depot.kind, depot.note, depot.fed_by} == {:tracking, "ETF-Sparplan", nil}
      assert {bargeld.kind, bargeld.closed, bargeld.note} == {:cash, true, "Aufgelöst"}

      groups = Categories.list_category_groups()

      assert Enum.map(groups, &{&1.name, &1.hidden, Enum.map(&1.categories, fn c -> c.name end)}) ==
               [
                 {"🏠 Wohnen", false, ["🏠 Miete", "⚡ Strom"]},
                 {"🛒 Alltag", false, ["🛒 Lebensmittel", "🎁 Geschenke", "🏋️ Sport", "📈 Sparplan"]},
                 {"📦 Alt", true, ["🧳 Urlaub"]}
               ]

      assert category("🎁 Geschenke").hidden
      assert category("🏠 Miete").note == "Warmmiete"
    end

    test "derives target versions and snoozes from the months" do
      {:ok, _report} = YnabImport.import_plan(@plan)

      groceries = category("🛒 Lebensmittel")

      assert %{amount: 30_000, set_aside: false} =
               Categories.target_for(groceries, ~D[2026-09-01])

      assert %{amount: 40_000, set_aside: false} =
               Categories.target_for(groceries, ~D[2026-10-01])

      assert %{cadence: :yearly, amount: 60_000, due_on: ~D[2026-12-15], set_aside: true} =
               Categories.target_for(category("⚡ Strom"), ~D[2026-08-01])

      assert Categories.target_snoozed?(category("🏋️ Sport"), ~D[2026-09-01])
      refute Categories.target_snoozed?(category("🏋️ Sport"), ~D[2026-10-01])
      assert Categories.target_for(category("📈 Sparplan"), ~D[2026-10-01]) == nil
    end

    test "books transfers, splits and their counterparts with YNAB's states and ids" do
      {:ok, _report} = YnabImport.import_plan(@plan)
      [giro, tagesgeld, depot, _bargeld] = Ledger.list_accounts()

      saving = booking(giro, ~D[2026-09-02])
      assert {saving.amount, saving.cleared, saving.memo} == {-20_000, :cleared, "Sparen"}
      counterpart = Repo.get!(Transaction, saving.transfer_transaction_id)

      assert {counterpart.account_id, counterpart.cleared, counterpart.flag} ==
               {tagesgeld.id, :uncleared, :purple}

      assert origins(saving) == ["t08"] and origins(counterpart) == ["t09"]

      split = booking(giro, ~D[2026-09-05])
      assert [groceries, small_change] = split.subtransactions
      assert {groceries.amount, groceries.category_id} == {-10_000, category("🛒 Lebensmittel").id}
      part_counterpart = Repo.get!(Transaction, small_change.transfer_transaction_id)
      assert {part_counterpart.account_id, part_counterpart.amount} == {tagesgeld.id, 5_000}
      assert origins(part_counterpart) == ["t11"]

      investing = booking(giro, ~D[2026-09-20])
      assert {investing.category_id, investing.flag} == {category("📈 Sparplan").id, :yellow}
      assert Repo.get!(Transaction, investing.transfer_transaction_id).account_id == depot.id

      assert Repo.all(from t in Transaction, select: t.source, distinct: true) == [:ynab]
      assert %{approved: false, category_id: nil} = booking(giro, ~D[2026-09-12])

      assert Repo.get_by!(Payee, name: "REWE").last_category_id == category("🛒 Lebensmittel").id
    end

    test "a second run gives the same content and a clean check" do
      {:ok, _report} = YnabImport.import_plan(@plan)
      first = content()

      assert {:ok, %Report{differences: []}} = YnabImport.import_plan(@plan)
      assert content() == first
    end

    test "replaces accounts that have a bank balance" do
      {:ok, _balance} =
        Ledger.put_bank_balance(account_fixture(), %{
          amount: 1,
          date: ~D[2026-10-07],
          source: :file
        })

      assert {:ok, %Report{}} = YnabImport.import_plan(@plan)
      assert Repo.aggregate(BankBalance, :count) == 0
    end

    test "lists what differs from YNAB and keeps the data" do
      plan =
        @plan
        |> update_month_category(
          "2026-09-01",
          "cat-lebensmittel",
          &Map.put(&1, "balance", -10_000)
        )
        |> update_in(["accounts", Access.at(1), "cleared_balance"], &(&1 + 10))

      assert {:ok, %Report{differences: differences}} = YnabImport.import_plan(plan)

      assert differences == [
               %{
                 where: "2026-09 🛒 Lebensmittel",
                 field: "available",
                 ynab: -10_000,
                 abakus: -15_000
               },
               %{
                 where: "🐷 Tagesgeld",
                 field: "cleared balance",
                 ynab: 1_060_010,
                 abakus: 1_060_000
               }
             ]

      assert length(Ledger.list_accounts()) == 4
    end

    test "refuses once a transaction did not come from YNAB, even a deleted one" do
      own = transaction_fixture()
      {:ok, _deleted} = Ledger.delete_transaction(own)

      assert YnabImport.import_plan(@plan) == {:error, :own_data}
      assert [%Account{}] = Ledger.list_accounts()
    end

    test "lists every case Abakus cannot represent and writes nothing" do
      {:ok, _report} = YnabImport.import_plan(@plan)
      before = content()

      plan =
        @plan
        |> update_in(["accounts", Access.at(0), "type"], fn _ -> "creditCard" end)
        |> update_month_category("2026-08-01", "cat-urlaub", &Map.put(&1, "goal_type", "TB"))
        |> update_month_category("2026-09-01", "cat-sport", &Map.put(&1, "goal_cadence", 2))
        |> update_in(["transactions", Access.at(4), "amount"], &(&1 - 1))

      assert {:error, {:unsupported, problems}} = YnabImport.import_plan(plan)

      assert problems == [
               "Account “💳 Girokonto” is of type creditCard.",
               "Category “🧳 Urlaub” has a target of type TB.",
               "Category “🏋️ Sport” has a target that repeats neither monthly nor yearly.",
               "Transaction t05 on 2026-08-10 has an amount that is not whole cents: -120.001."
             ]

      assert content() == before
    end

    test "keeps the budget it had when writing the plan fails" do
      {:ok, _report} = YnabImport.import_plan(@plan)
      before = content()
      reserved = &Map.put(&1, "name", "Inflow: Ready to Assign")
      plan = update_in(@plan, ["categories", Access.filter(&(&1["id"] == "cat-miete"))], reserved)

      assert {:error, {:not_written, message}} = YnabImport.import_plan(plan)
      assert message =~ "category Inflow: Ready to Assign"
      assert message =~ "ist für „Zu verteilen“ reserviert"
      assert content() == before
    end
  end

  describe "run/3" do
    test "imports the token's only plan" do
      FakeYnab.start(%{"plan-test" => @plan})

      assert {:ok, %Report{plan: "Testhaushalt", differences: []}} =
               YnabImport.run(FakeYnab.token())
    end

    test "with several plans, asks for one, and imports the one given" do
      FakeYnab.start(%{
        "plan-a" => %{@plan | "name" => "A"},
        "plan-b" => %{@plan | "name" => "B"}
      })

      assert YnabImport.run(FakeYnab.token()) ==
               {:error, {:choose_plan, [{"plan-a", "A"}, {"plan-b", "B"}]}}

      assert {:ok, %Report{plan: "B"}} = YnabImport.run(FakeYnab.token(), "plan-b")
    end

    # A FunctionClauseError would print the token among its arguments.
    test "refuses a plan id that is no string, without fetching" do
      assert YnabImport.run("secret", ~c"plan-test") == {:error, :bad_plan_id}
      assert YnabImport.run("secret", "") == {:error, :bad_plan_id}
      refute YnabImport.error_lines(:bad_plan_id) |> Enum.join() |> String.contains?("secret")
    end

    test "passes on YNAB's answer when it refuses" do
      FakeYnab.start(%{})

      assert YnabImport.run("wrong") == {:error, {:ynab, 401, "Unauthorized"}}
      assert YnabImport.run(FakeYnab.token()) == {:error, :no_plans}
    end
  end

  describe "Report.lines/1" do
    test "names what was imported, the merged payees and the differences" do
      report = %Report{
        plan: "Testhaushalt",
        counts: %{accounts: 4, categories: 7, payees: 5, transactions: 18},
        merged_payees: [{"REWE", ["Rewe", "rewe"]}],
        differences: [
          %{where: "2026-09 🛒 Lebensmittel", field: "underfunded", ynab: 33_335, abakus: nil}
        ]
      }

      assert Report.lines(report) == [
               "Imported “Testhaushalt”: 4 accounts, 7 categories, 5 payees, 18 transactions.",
               "Merged payees with the same name: “REWE” takes in “Rewe”, “rewe”.",
               "1 difference from YNAB:",
               "  2026-09 🛒 Lebensmittel, underfunded: YNAB 33.335, Abakus none"
             ]

      assert List.last(Report.lines(%{report | differences: []})) ==
               "Every month, category and account matches YNAB."
    end
  end

  defp category(name), do: Repo.get_by!(Category, name: name)

  defp booking(account, date) do
    Repo.one!(
      from t in Ledger.in_register(),
        where: t.account_id == ^account.id and t.date == ^date,
        preload: :subtransactions
    )
  end

  defp origins(transaction),
    do:
      transaction |> Repo.preload(:origins) |> Map.fetch!(:origins) |> Enum.map(& &1.external_id)

  defp update_month_category(plan, month, category_id, fun) do
    update_in(
      plan,
      ["months", Access.filter(&(&1["month"] == month)), "categories"],
      fn categories ->
        Enum.map(categories, &if(&1["id"] == category_id, do: fun.(&1), else: &1))
      end
    )
  end

  # What the budget holds, without ids and timestamps.
  defp content do
    accounts = names(Account)
    groups = names(CategoryGroup)
    categories = names(Category)
    payees = names(Payee)

    %{
      accounts:
        Enum.map(
          Ledger.list_accounts(),
          &Map.take(&1, [:name, :kind, :fed_by, :closed, :note, :position, :last_reconciled_at])
        ),
      groups:
        Enum.map(
          Repo.all(from g in CategoryGroup, order_by: [g.position, g.id]),
          &Map.take(&1, [:name, :hidden, :internal, :position, :note])
        ),
      categories:
        sorted(
          Category,
          &{&1.name, &1.hidden, &1.position, &1.note, groups[&1.category_group_id]}
        ),
      payees:
        sorted(
          Payee,
          &{&1.name, accounts[&1.transfer_account_id], categories[&1.last_category_id]}
        ),
      assignments: sorted(Assignment, &{categories[&1.category_id], &1.month, &1.amount}),
      targets:
        sorted(
          TargetVersion,
          &{categories[&1.category_id], &1.from_month, &1.cadence, &1.amount, &1.due_on}
        ),
      snoozes: sorted(TargetSnooze, &{categories[&1.category_id], &1.month}),
      transactions:
        Transaction
        |> Repo.all()
        |> Repo.preload([:subtransactions, :origins])
        |> Enum.map(fn t ->
          {accounts[t.account_id], t.date, t.amount, payees[t.payee_id],
           categories[t.category_id], t.memo, t.cleared, t.approved, t.flag, t.source,
           Enum.map(t.origins, & &1.external_id),
           Enum.map(
             t.subtransactions,
             &{&1.amount, categories[&1.category_id], payees[&1.payee_id], &1.memo}
           )}
        end)
        |> Enum.sort()
    }
  end

  defp names(schema), do: Map.new(Repo.all(schema), &{&1.id, &1.name})

  defp sorted(schema, fun), do: schema |> Repo.all() |> Enum.map(fun) |> Enum.sort()
end
