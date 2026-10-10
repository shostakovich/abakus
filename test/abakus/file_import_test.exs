defmodule Abakus.FileImportTest do
  use Abakus.DataCase

  import Abakus.DomainFixtures

  alias Abakus.{FileImport, Ledger}
  alias Abakus.Ledger.{Account, BankBalance, Payee, Transaction}

  defp statement(name) do
    {:ok, [statement]} = FileImport.read(File.read!("test/fixtures/ofx/#{name}"))
    statement
  end

  defp register(account), do: account |> Ledger.list_transactions() |> Enum.reverse()

  setup do
    %{giro: account_fixture(name: "💶 Girokonto")}
  end

  describe "import/1" do
    test "a fictional export imports without duplicates; re-importing an overlapping one adds nothing more",
         %{giro: giro} do
      september = statement("girokonto_2026-09.ofx")
      october = statement("girokonto_2026-10.ofx")

      assert {:ok, %{new: 4, matched: 0}} = FileImport.import([{september, giro}])
      assert {:ok, %{new: 2, matched: 0}} = FileImport.import([{october, giro}])
      assert {:ok, %{new: 0, matched: 0}} = FileImport.import([{october, giro}])
      assert {:ok, %{new: 0, matched: 0}} = FileImport.import([{september, giro}])

      assert giro |> register() |> Enum.map(& &1.amount) ==
               [250_000, -640, -5_837, -1_200, -4_200, 3_490]

      assert Ledger.balances()[giro.id].balance == 241_613

      assert Ledger.existing_external_ids(giro, :file, ~w(MM-0001 MM-0006)) ==
               MapSet.new(~w(MM-0001 MM-0006))
    end

    test "imports land unapproved and cleared, with payee and memo from the file", %{giro: giro} do
      market = payee_fixture(name: "🛒 Frischmarkt")

      {:ok, %{new: 4, matched: 0}} =
        FileImport.import([{statement("girokonto_2026-09.ofx"), giro}])

      assert [salary, bakery, groceries, library] = register(giro)

      assert %Transaction{
               date: ~D[2026-09-01],
               amount: 250_000,
               memo: "Gehalt September",
               cleared: :cleared,
               approved: false,
               source: :file,
               category_id: nil
             } = salary

      assert salary.payee.name == "Arbeitgeber Muster GmbH"
      assert bakery.payee.name == "Bäckerei Korn"
      assert groceries.payee_id == market.id
      assert library.memo == nil
      assert Repo.aggregate(from(p in Payee, where: is_nil(p.transfer_account_id)), :count) == 4
    end

    test "remembers the file's account on the account", %{giro: giro} do
      statement = statement("girokonto_2026-09.ofx")
      assert FileImport.linked_account(statement) == nil

      {:ok, _counts} = FileImport.import([{statement, giro}])

      assert FileImport.linked_account(statement).id == giro.id
      assert FileImport.linked_account(statement("kreditkarte.ofx")) == nil
    end

    test "keeps the ledger balance as the account's bank balance from the file", %{giro: giro} do
      {:ok, _counts} = FileImport.import([{statement("girokonto_2026-09.ofx"), giro}])
      {:ok, _counts} = FileImport.import([{statement("girokonto_2026-10.ofx"), giro}])
      {:ok, _counts} = FileImport.import([{statement("girokonto_2026-10.ofx"), giro}])

      assert giro.id
             |> then(
               &Repo.all(from b in BankBalance, where: b.account_id == ^&1, order_by: b.date)
             )
             |> Enum.map(&{&1.date, &1.amount, &1.source}) ==
               [{~D[2026-09-30], 242_323, :file}, {~D[2026-10-07], 241_613, :file}]
    end

    test "does not bring back a transaction deleted after its import", %{giro: giro} do
      {:ok, %{new: 4, matched: 0}} =
        FileImport.import([{statement("girokonto_2026-09.ofx"), giro}])

      library = giro |> register() |> List.last()
      {:ok, _deleted} = Ledger.delete_transaction(library)

      assert {:ok, %{new: 2, matched: 0}} =
               FileImport.import([{statement("girokonto_2026-10.ofx"), giro}])

      refute Enum.any?(register(giro), &(&1.memo == nil and &1.amount == -1_200))
    end

    test "dedupes per account, so another account takes the same FITIDs", %{giro: giro} do
      other = account_fixture()

      {:ok, %{new: 4, matched: 0}} =
        FileImport.import([{statement("girokonto_2026-09.ofx"), giro}])

      assert {:ok, %{new: 4, matched: 0}} =
               FileImport.import([{statement("girokonto_2026-09.ofx"), other}])
    end

    test "takes a FITID twice in one file once", %{giro: giro} do
      statement = statement("girokonto_2026-09.ofx")
      [first | _rest] = statement.transactions
      statement = %{statement | transactions: [first | statement.transactions]}

      assert {:ok, %{new: 4, matched: 0}} = FileImport.import([{statement, giro}])
    end

    test "imports several statements at once, all or none", %{giro: giro} do
      card = account_fixture(name: "Karte")
      september = statement("girokonto_2026-09.ofx")

      broken = %{
        statement("kreditkarte.ofx")
        | transactions: [%{hd(september.transactions) | amount: 10_000_000_000_001}]
      }

      assert {:error, {%{fitid: "MM-0001"}, changeset}} =
               FileImport.import([{september, giro}, {broken, card}])

      assert %{amount: [_]} = errors_on(changeset)
      assert Repo.aggregate(Transaction, :count) == 0
      assert Repo.aggregate(BankBalance, :count) == 0
      assert Repo.reload!(giro).ofx_acct_id == nil

      assert {:ok, %{new: 6, matched: 0}} =
               FileImport.import([{september, giro}, {statement("kreditkarte.ofx"), card}])
    end

    test "refuses two statements into one account", %{giro: giro} do
      assert FileImport.import([
               {statement("girokonto_2026-09.ofx"), giro},
               {statement("kreditkarte.ofx"), giro}
             ]) == {:error, "Zwei Konten der Datei gehen nicht in dasselbe Konto."}
    end

    test "refuses accounts fed by another app and closed ones" do
      statement = statement("girokonto_2026-09.ofx")

      for attrs <- [
            %{fed_by: :shared_expenses},
            %{fed_by: :portfolio, kind: :tracking},
            %{closed: true}
          ] do
        account = account_fixture(attrs)

        assert FileImport.import([{statement, account}]) ==
                 {:error, "#{account.name} nimmt keinen Datei-Import."}
      end

      assert Repo.aggregate(Transaction, :count) == 0
    end
  end

  describe "matching" do
    setup %{giro: giro} do
      bakery =
        transaction_fixture(
          account_id: giro.id,
          date: ~D[2026-09-05],
          amount: -640,
          memo: "Brötchen",
          category_id: category_fixture().id
        )

      %{bakery: bakery}
    end

    test "proposes a match for an existing transaction, never merges it silently",
         %{giro: giro, bakery: bakery} do
      preview = FileImport.preview(statement("girokonto_2026-09.ofx"), giro)

      assert {preview.new, preview.existing, preview.matched, preview.reconciled} == {3, 0, 1, 0}
      assert %{status: :matched, match: %{id: id}} = Enum.at(preview.rows, 1)
      assert id == bakery.id

      assert {:ok, %{new: 3, matched: 1}} =
               FileImport.import([{statement("girokonto_2026-09.ofx"), giro}])

      assert [%Transaction{matched_transaction_id: ^id, approved: false, date: ~D[2026-09-03]}] =
               Ledger.list_match_proposals(giro)

      assert %Transaction{date: ~D[2026-09-05], cleared: :uncleared, memo: "Brötchen"} =
               Repo.reload!(bakery)

      assert length(register(giro)) == 4
      assert Ledger.balances()[giro.id].balance == 250_000 - 640 - 5_837 - 1_200
    end

    test "an accepted or rejected match is not imported again", %{giro: giro} do
      {:ok, %{matched: 1}} = FileImport.import([{statement("girokonto_2026-09.ofx"), giro}])
      [proposal] = Ledger.list_match_proposals(giro)
      {:ok, _merged} = Ledger.accept_match(proposal)

      assert {:ok, %{new: 0, matched: 0}} =
               FileImport.import([{statement("girokonto_2026-09.ofx"), giro}])

      other = account_fixture()
      transaction_fixture(account_id: other.id, date: ~D[2026-09-03], amount: -640)
      {:ok, %{matched: 1}} = FileImport.import([{statement("girokonto_2026-09.ofx"), other}])
      [proposal] = Ledger.list_match_proposals(other)
      {:ok, _separated} = Ledger.reject_match(proposal)

      assert {:ok, %{new: 0, matched: 0}} =
               FileImport.import([{statement("girokonto_2026-09.ofx"), other}])

      assert length(register(other)) == 5
    end

    test "skips the rows dated up to the newest reconciled transaction", %{giro: giro} do
      transaction_fixture(account_id: giro.id, date: ~D[2026-09-15], cleared: :reconciled)

      preview = FileImport.preview(statement("girokonto_2026-09.ofx"), giro)

      assert Enum.map(preview.rows, & &1.status) == [:reconciled, :reconciled, :reconciled, :new]
      assert {preview.new, preview.matched, preview.reconciled} == {1, 0, 3}

      assert {:ok, %{new: 1, matched: 0}} =
               FileImport.import([{statement("girokonto_2026-09.ofx"), giro}])

      assert Ledger.list_match_proposals(giro) == []
    end

    test "a FITID there already counts as there, also before the last reconcile", %{giro: giro} do
      {:ok, %{new: 3, matched: 1}} =
        FileImport.import([{statement("girokonto_2026-09.ofx"), giro}])

      transaction_fixture(account_id: giro.id, date: ~D[2026-09-30], cleared: :reconciled)

      preview = FileImport.preview(statement("girokonto_2026-10.ofx"), giro)

      assert Enum.map(preview.rows, & &1.status) == [:existing, :existing, :new, :new]
    end
  end

  describe "preview/2" do
    test "counts what is new and what is there already", %{giro: giro} do
      {:ok, %{new: 4, matched: 0}} =
        FileImport.import([{statement("girokonto_2026-09.ofx"), giro}])

      preview = FileImport.preview(statement("girokonto_2026-10.ofx"), giro)

      assert {preview.new, preview.existing, preview.matched, preview.reconciled} == {2, 2, 0, 0}

      assert Enum.map(preview.rows, &{&1.transaction.fitid, &1.status}) == [
               {"MM-0003", :existing},
               {"MM-0004", :existing},
               {"MM-0005", :new},
               {"MM-0006", :new}
             ]
    end

    test "without an account, everything is new" do
      preview = FileImport.preview(statement("girokonto_2026-09.ofx"), nil)

      assert {preview.new, preview.existing, preview.matched, preview.reconciled} == {4, 0, 0, 0}
    end
  end

  describe "accounts/0 and linked_account/1" do
    test "offer the open accounts that are not fed by another app", %{giro: giro} do
      cash = account_fixture(kind: :cash)
      depot = account_fixture(kind: :tracking)
      account_fixture(fed_by: :shared_expenses)
      account_fixture(kind: :tracking, fed_by: :portfolio)
      account_fixture(closed: true)

      assert Enum.map(FileImport.accounts(), & &1.id) == [giro.id, cash.id, depot.id]
    end

    test "a linked account that no longer takes a file import is not offered", %{giro: giro} do
      statement = statement("girokonto_2026-09.ofx")
      {:ok, _counts} = FileImport.import([{statement, giro}])
      {:ok, _giro} = Ledger.update_account(giro, %{closed: true})

      assert FileImport.linked_account(statement) == nil
      assert %Account{} = Ledger.get_account_by_ofx(statement.bank_id, statement.acct_id)
    end
  end
end
