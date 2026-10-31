defmodule Abakus.Sync.ScenariosTest do
  use Abakus.DataCase

  import Abakus.DomainFixtures

  alias Abakus.{Budget, Categories, Ids, Ledger, SyncDevice}
  alias Abakus.Categories.{Assignment, Category}
  alias Abakus.Ledger.{Payee, Transaction}

  @november ~D[2026-11-01]

  setup do
    fix_now(~U[2026-11-02 09:00:00Z])
    %{scope: budget_scope(), giro: account_fixture(name: "Girokonto")}
  end

  defp rewe(c, category) do
    transaction_fixture(
      account_id: c.giro.id,
      payee_name: "Rewe",
      amount: -4_210,
      date: ~D[2026-11-02],
      category_id: category.id
    )
  end

  describe "scenario: edits of different fields both stay" do
    test "the Mac's memo and the web's category", c do
      groceries = category_fixture(name: "Lebensmittel")
      household = category_fixture(name: "Haushalt")
      rewe = rewe(c, groceries)
      mac = SyncDevice.new(c.scope, "mac")

      mac =
        SyncDevice.edit(
          mac,
          "transactions",
          rewe.id,
          %{memo: "Wocheneinkauf"},
          ~U[2026-11-02 10:05:00Z]
        )

      fix_now(~U[2026-11-02 10:00:00Z])
      {:ok, _rewe} = Ledger.update_transaction(c.scope, rewe, %{category_id: household.id})
      mac = SyncDevice.sync(mac)

      assert %Transaction{memo: "Wocheneinkauf", category_id: category_id} = Repo.reload(rewe)
      assert category_id == household.id
      SyncDevice.assert_converged(mac, Transaction, rewe.id)
    end
  end

  describe "scenario: the later edit of one field wins" do
    test "the Mac's amount at 10:05 over the web's at 10:00", c do
      rewe = rewe(c, category_fixture())
      mac = SyncDevice.new(c.scope, "mac")

      fix_now(~U[2026-11-02 10:00:00Z])
      {:ok, _rewe} = Ledger.update_transaction(c.scope, rewe, %{amount: -4_210, memo: "Web"})

      mac =
        SyncDevice.edit(mac, "transactions", rewe.id, %{amount: -4_500}, ~U[2026-11-02 10:05:00Z])

      fix_now(~U[2026-11-02 11:00:00Z])
      mac = SyncDevice.sync(mac)

      assert Repo.reload(rewe).amount == -4_500
      SyncDevice.assert_converged(mac, Transaction, rewe.id)
    end
  end

  describe "scenario: an offline assignment to a deleted category goes to its successor" do
    test "Bücher shows 32,00 € Zugewiesen in November", c do
      magazines = category_fixture(name: "Zeitschriften")
      books = category_fixture(name: "Bücher")
      {:ok, _assigned} = Categories.assign(c.scope, books, @november, 2_000)
      mac = SyncDevice.new(c.scope, "mac")

      fix_now(~U[2026-11-02 10:00:00Z])
      {:ok, _deleted} = Categories.delete_category(c.scope, magazines, books)
      assignment = Ids.assignment(magazines.id, @november)

      mac =
        mac
        |> SyncDevice.edit(
          "assignments",
          assignment,
          %{category_id: magazines.id, month: "2026-11-01", amount: 1_200},
          ~U[2026-11-02 10:05:00Z]
        )
        |> SyncDevice.sync()

      assert assigned(c.scope, books) == 3_200
      SyncDevice.assert_converged(mac, Category, magazines.id)
      SyncDevice.assert_converged(mac, Assignment, assignment)
      assert assigned_on(mac, books) == 3_200
    end
  end

  describe "scenario: two devices create the same payee" do
    test "both list one payee Bäckerei Korn with both transactions", c do
      mac = SyncDevice.new(c.scope, "mac")
      at = ~U[2026-11-02 10:05:00Z]
      {payee, booked} = {Ids.generate(), Ids.generate()}

      mac =
        mac
        |> SyncDevice.edit("payees", payee, %{name: "Bäckerei Korn", hidden: false}, at)
        |> SyncDevice.edit(
          "transactions",
          booked,
          %{
            account_id: c.giro.id,
            date: "2026-11-02",
            amount: -650,
            payee_id: payee,
            cleared: "uncleared",
            approved: true,
            source: "manual"
          },
          at
        )

      fix_now(~U[2026-11-02 10:10:00Z])
      web = transaction_fixture(account_id: c.giro.id, payee_name: "Bäckerei Korn", amount: -420)
      mac = SyncDevice.sync(mac)

      assert [%Payee{id: korn, name: "Bäckerei Korn"}] =
               Enum.filter(Ledger.list_payees(c.scope), &(&1.name == "Bäckerei Korn"))

      assert Repo.get!(Transaction, booked).payee_id == korn
      assert Repo.reload(web).payee_id == korn

      for id <- [payee, Repo.reload(web).payee_id, web.payee_id] do
        SyncDevice.assert_converged(mac, Payee, id)
      end

      SyncDevice.assert_converged(mac, Transaction, booked)
      SyncDevice.assert_converged(mac, Transaction, web.id)
    end
  end

  defp assigned(scope, category) do
    scope
    |> Categories.budget()
    |> Budget.months(@november)
    |> Enum.find(&(&1.month == @november))
    |> Map.fetch!(:categories)
    |> Enum.find(&(&1.category_id == category.id))
    |> Map.fetch!(:assigned)
  end

  defp assigned_on(device, category) do
    categories = SyncDevice.rows(device, "categories")

    successor = fn id ->
      case categories[id] do
        %{"deleted_at" => deleted, "successor_id" => next} when not is_nil(deleted) -> next
        _alive -> id
      end
    end

    for {_id, %{"category_id" => id, "month" => "2026-11-01", "amount" => amount} = row} <-
          SyncDevice.rows(device, "assignments"),
        is_nil(row["deleted_at"]),
        successor.(id) == category.id,
        reduce: 0,
        do: (sum -> sum + amount)
  end
end
