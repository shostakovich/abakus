defmodule Abakus.ImportTest do
  use Abakus.DataCase

  import Abakus.DomainFixtures

  alias Abakus.{Import, Ledger}
  alias Abakus.Ledger.{BankBalance, Transaction}

  defp entry(external_id, date, amount, attrs \\ %{}) do
    Map.merge(
      %{external_id: external_id, date: date, amount: amount, payee_name: nil, memo: nil},
      attrs
    )
  end

  defp entries do
    [
      entry("B-1", ~D[2026-10-01], 250_000, %{
        payee_name: "Arbeitgeber Muster GmbH",
        memo: "Gehalt"
      }),
      entry("B-2", ~D[2026-10-03], -640, %{payee_name: "Bäckerei Korn"}),
      entry("B-3", ~D[2026-10-05], -5_837, %{payee_name: "Frischmarkt"})
    ]
  end

  defp register(account),
    do: budget_scope() |> Ledger.list_transactions(account) |> Enum.reverse()

  setup do
    %{giro: account_fixture(name: "Girokonto")}
  end

  describe "import/4" do
    test "brings the new entries in unapproved and cleared from the source", %{giro: giro} do
      assert Import.import(budget_scope(), giro, :bank, entries()) == {:ok, %{new: 3, matched: 0}}

      assert [salary, bakery, _groceries] = register(giro)

      assert %Transaction{
               date: ~D[2026-10-01],
               amount: 250_000,
               memo: "Gehalt",
               cleared: :cleared,
               approved: false,
               source: :bank
             } = salary

      assert salary.payee.name == "Arbeitgeber Muster GmbH"
      assert bakery.memo == nil

      assert Ledger.existing_external_ids(budget_scope(), giro, :bank, ~w(B-1 B-2 B-3)) ==
               MapSet.new(~w(B-1 B-2 B-3))
    end

    test "dedupes by account, source and external id", %{giro: giro} do
      {:ok, _counts} = Import.import(budget_scope(), giro, :bank, entries())

      assert Import.import(budget_scope(), giro, :bank, entries() ++ entries()) ==
               {:ok, %{new: 0, matched: 0}}

      assert {:ok, %{new: 3}} = Import.import(budget_scope(), account_fixture(), :bank, entries())
      assert {:ok, %{new: 0, matched: 3}} = Import.import(budget_scope(), giro, :file, entries())
    end

    test "proposes matches and skips what is dated up to the newest reconciled transaction",
         %{giro: giro} do
      transaction_fixture(account_id: giro.id, date: ~D[2026-10-02], cleared: :reconciled)
      bakery = transaction_fixture(account_id: giro.id, date: ~D[2026-10-04], amount: -640)

      assert Import.import(budget_scope(), giro, :bank, entries()) == {:ok, %{new: 1, matched: 1}}

      assert [%Transaction{matched_transaction_id: id, source: :bank}] =
               Ledger.list_match_proposals(budget_scope(), giro)

      assert id == bakery.id
    end

    test "refuses an entry the Ledger refuses with the entry", %{giro: giro} do
      broken = entry("B-9", ~D[2026-10-09], 10_000_000_000_001)

      assert {:error, {^broken, changeset}} =
               Import.import(budget_scope(), giro, :bank, entries() ++ [broken])

      assert %{amount: [_]} = errors_on(changeset)
      assert Repo.aggregate(Transaction, :count) == 0
    end
  end

  describe "rows/4" do
    test "gives each unique entry its status and match", %{giro: giro} do
      {:ok, _counts} = Import.import(budget_scope(), giro, :bank, Enum.take(entries(), 1))
      bakery = transaction_fixture(account_id: giro.id, date: ~D[2026-10-04], amount: -640)

      assert [
               %{transaction: %{external_id: "B-1"}, status: :existing, match: nil},
               %{transaction: %{external_id: "B-2"}, status: :matched, match: %{id: id}},
               %{transaction: %{external_id: "B-3"}, status: :new, match: nil}
             ] = Import.rows(budget_scope(), giro, :bank, entries() ++ entries())

      assert id == bakery.id
    end

    test "without an account, every entry is new" do
      assert Enum.map(Import.rows(budget_scope(), nil, :bank, entries()), & &1.status) ==
               [:new, :new, :new]
    end
  end

  describe "put_bank_balance/4" do
    test "keeps the balance under the source, one per date", %{giro: giro} do
      balance = %{date: ~D[2026-10-07], amount: 241_613}

      assert Import.put_bank_balance(budget_scope(), giro, :bank, balance) == :ok

      assert Import.put_bank_balance(budget_scope(), giro, :bank, %{balance | amount: 241_000}) ==
               :ok

      assert Import.put_bank_balance(budget_scope(), giro, :bank, nil) == :ok

      assert [%BankBalance{source: :bank, date: ~D[2026-10-07], amount: 241_000}] =
               Repo.all(BankBalance)
    end
  end
end
