defmodule AbakusWeb.RegisterLive.RowsTest do
  use ExUnit.Case, async: true

  alias Abakus.Categories.Category
  alias Abakus.Ledger.{Account, Payee, Subtransaction, Transaction}
  alias Abakus.Names
  alias AbakusWeb.RegisterLive.Rows

  @giro %Account{id: 1, kind: :checking}
  @savings %Account{id: 2, kind: :savings}
  @depot %Account{id: 3, kind: :tracking}
  @accounts Map.new([@giro, @savings, @depot], &{&1.id, &1})

  defp payee(name, transfer_account \\ nil),
    do: %Payee{
      name: name,
      lookup_key: Names.lookup_key(name),
      transfer_account_id: transfer_account
    }

  defp category(name, internal \\ false),
    do: %Category{name: name, lookup_key: Names.lookup_key(name), internal: internal}

  defp transaction(id, attrs) do
    struct!(
      %Transaction{
        id: id,
        account_id: @giro.id,
        date: ~D[2026-10-01],
        amount: -1_000,
        cleared: :cleared,
        approved: true,
        subtransactions: []
      },
      attrs
    )
  end

  describe "filter/2" do
    setup do
      %{
        rows: [
          transaction(1, approved: false),
          transaction(2, cleared: :uncleared),
          transaction(3, cleared: :reconciled)
        ]
      }
    end

    test "all keeps every transaction", %{rows: rows} do
      assert Rows.filter(rows, :all) == rows
    end

    test "unapproved keeps those waiting for approval", %{rows: rows} do
      assert Enum.map(Rows.filter(rows, :unapproved), & &1.id) == [1]
    end

    test "uncleared keeps those the bank does not have yet", %{rows: rows} do
      assert Enum.map(Rows.filter(rows, :uncleared), & &1.id) == [2]
    end
  end

  describe "search/2" do
    setup do
      %{
        rows: [
          transaction(1, payee: payee("🛒 Frischmarkt"), memo: "Wocheneinkauf"),
          transaction(2, category: category("🍕 Restaurants"), amount: -4_875),
          transaction(3, category: category("Inflow: Ready to Assign", true), amount: 324_000),
          transaction(4,
            payee: payee("Drogerie"),
            subtransactions: [
              %Subtransaction{category: category("Haushalt"), memo: "Straße fegen"},
              %Subtransaction{payee: payee("Apotheke")}
            ]
          )
        ]
      }
    end

    defp found(rows, query), do: rows |> Rows.search(query) |> Enum.map(& &1.id)

    test "finds payee, category and memo by their lookup key", %{rows: rows} do
      assert found(rows, "frischmarkt") == [1]
      assert found(rows, " WOCHEN ") == [1]
      assert found(rows, "restaurant") == [2]
    end

    test "finds Ready to Assign by its German name", %{rows: rows} do
      assert found(rows, "zu verteilen") == [3]
    end

    test "finds the parts of a split", %{rows: rows} do
      assert found(rows, "haushalt") == [4]
      assert found(rows, "strasse") == [4]
      assert found(rows, "apotheke") == [4]
    end

    test "finds amounts as the register shows them", %{rows: rows} do
      assert found(rows, "48,75") == [2]
      assert found(rows, "3.240") == [3]
    end

    test "an empty query finds everything", %{rows: rows} do
      assert found(rows, "  ") == [1, 2, 3, 4]
    end
  end

  test "searching?/1 tells whether the query narrows anything" do
    assert Rows.searching?("Rewe")
    refute Rows.searching?("  ")
  end

  describe "categorisable?/2" do
    test "a transaction in a budget account" do
      assert Rows.categorisable?(transaction(1, []), @accounts)
      assert Rows.categorisable?(transaction(1, payee: payee("Bäcker")), @accounts)
    end

    test "a transfer to a tracking account, which needs a category" do
      transfer = transaction(1, payee: payee("Transfer : Depot", @depot.id))
      assert Rows.categorisable?(transfer, @accounts)
    end

    test "not a transfer between budget accounts" do
      transfer = transaction(1, payee: payee("Transfer : Sparen", @savings.id))
      refute Rows.categorisable?(transfer, @accounts)
    end

    test "not in a tracking account" do
      refute Rows.categorisable?(transaction(1, account_id: @depot.id), @accounts)
    end

    test "not a split" do
      refute Rows.categorisable?(
               transaction(1, subtransactions: [%Subtransaction{}, %Subtransaction{}]),
               @accounts
             )
    end
  end

  describe "needs_category?" do
    test "a transaction without a category in a budget account" do
      assert Rows.needs_category?(transaction(1, []), @accounts)
      refute Rows.needs_category?(transaction(1, category_id: 7), @accounts)
    end

    test "not at zero, as the view leaves it out" do
      refute Rows.needs_category?(transaction(1, amount: 0), @accounts)
    end

    test "a transfer only to a tracking account" do
      assert Rows.needs_category?(transaction(1, payee: payee("Depot", @depot.id)), @accounts)
      refute Rows.needs_category?(transaction(1, payee: payee("Sparen", @savings.id)), @accounts)
    end

    test "not in a tracking account" do
      refute Rows.needs_category?(transaction(1, account_id: @depot.id), @accounts)
    end

    test "a split only in its parts" do
      to_depot = %Subtransaction{amount: -500, payee: payee("Depot", @depot.id)}
      to_savings = %Subtransaction{amount: -500, payee: payee("Sparen", @savings.id)}
      split = transaction(1, subtransactions: [to_depot, to_savings])

      refute Rows.needs_category?(split, @accounts)
      assert Rows.needs_category?(to_depot, split, @accounts)
      refute Rows.needs_category?(to_savings, split, @accounts)
      refute Rows.needs_category?(%Subtransaction{amount: 0}, split, @accounts)
      refute Rows.needs_category?(%Subtransaction{amount: -500, category_id: 7}, split, @accounts)
    end
  end
end
