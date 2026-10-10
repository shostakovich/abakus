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

  test "running/2 gives the balance after each transaction, newest first" do
    rows = [
      transaction(3, amount: -500),
      transaction(2, amount: 2_000),
      transaction(1, amount: -1_000)
    ]

    assert Rows.running(rows, 500) == %{3 => 500, 2 => 1_000, 1 => -1_000}
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
end
