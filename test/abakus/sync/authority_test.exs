defmodule Abakus.Sync.AuthorityTest do
  use Abakus.DataCase

  import Abakus.DomainFixtures
  import Abakus.KasseFixtures

  alias Abakus.Depot.PortfoliosFixtures
  alias Abakus.{Ids, Ledger, SyncDevice}
  alias Abakus.Kasse.{BudgetLink, Expenses}
  alias Abakus.Ledger.{Account, Subtransaction, Transaction}

  @at ~U[2026-11-02 10:05:00Z]

  setup do
    fix_now(~U[2026-11-02 10:00:00Z])
    h = household()
    shared = account_fixture(%{name: "Geteilt", kind: :cash})
    checking = account_fixture(%{name: "Girokonto", kind: :checking})
    {:ok, _created} = BudgetLink.switch_on(scope_of(h.anna), shared.id)
    %{h: h, scope: budget_scope(), shared: shared, checking: checking}
  end

  defp led(expense),
    do:
      Repo.one!(
        from t in Transaction, where: t.kasse_expense_id == ^expense.id and is_nil(t.deleted_at)
      )

  defp market(c) do
    expense = create!(equal(c.h, "Markt", 3000, "2026-11-02", c.h.ben, [c.h.anna]), c.h.anna)
    led(expense)
  end

  describe "scenario: a device cannot change what the Kasse leads" do
    test "the server keeps -30,00 €, and the app shows it after its next sync", c do
      transaction = market(c)
      assert transaction.amount == -3000
      mac = SyncDevice.new(c.scope, "mac")

      mac =
        mac
        |> SyncDevice.edit(
          "transactions",
          transaction.id,
          %{amount: -3500, memo: "Wochenmarkt"},
          @at
        )
        |> SyncDevice.sync()

      assert %Transaction{amount: -3000, memo: "Wochenmarkt"} = Repo.reload(transaction)
      assert SyncDevice.row(mac, "transactions", transaction.id)["amount"] == -3000
      SyncDevice.assert_converged(mac, Transaction, transaction.id)
    end
  end

  describe "a deleted led transaction" do
    test "stays deleted once its source is gone", c do
      deposit =
        PortfoliosFixtures.transaction_fixture(c.scope, ~D[2026-11-02],
          type: :deposit,
          amount: 100
        )

      led_by = {:depot_transaction, deposit.id}

      {:ok, transaction} =
        Ledger.create_transaction(
          c.scope,
          %{account_id: c.checking.id, date: ~D[2026-11-02], amount: 10_000},
          led_by: led_by
        )

      {:ok, _deleted} = Ledger.delete_transaction(c.scope, transaction, led_by: led_by)
      Repo.delete!(deposit)

      assert %Transaction{depot_transaction_id: nil, led_by: :depot} = Repo.reload(transaction)

      mac =
        c.scope
        |> SyncDevice.new("mac")
        |> SyncDevice.edit("transactions", transaction.id, %{deleted_at: nil, amount: 1}, @at)
        |> SyncDevice.sync()

      assert %Transaction{deleted_at: %DateTime{}, amount: 10_000} = Repo.reload(transaction)
      SyncDevice.assert_converged(mac, Transaction, transaction.id)
    end
  end

  describe "led_by" do
    test "names the area for the devices, and only the server writes it", c do
      transaction = market(c)
      mac = SyncDevice.new(c.scope, "mac")
      assert SyncDevice.row(mac, "transactions", transaction.id)["led_by"] == "kasse"

      own = transaction_fixture(account_id: c.checking.id)

      mac =
        mac
        |> SyncDevice.edit("transactions", transaction.id, %{led_by: nil}, @at)
        |> SyncDevice.edit("transactions", own.id, %{led_by: "depot"}, @at)
        |> SyncDevice.sync()

      assert Repo.reload(transaction).led_by == :kasse
      assert Repo.reload(own).led_by == nil
      SyncDevice.assert_converged(mac, Transaction, transaction.id)
      SyncDevice.assert_converged(mac, Transaction, own.id)
    end
  end

  describe "fields only the server writes" do
    test "a transaction's match and an account's shared expenses", c do
      own = transaction_fixture(account_id: c.checking.id)
      other = transaction_fixture(account_id: c.checking.id)

      mac =
        c.scope
        |> SyncDevice.new("mac")
        |> SyncDevice.edit("transactions", own.id, %{matched_transaction_id: other.id}, @at)
        |> SyncDevice.edit("accounts", c.checking.id, %{shared_expenses: true}, @at)
        |> SyncDevice.edit("accounts", c.shared.id, %{shared_expenses: false}, @at)
        |> SyncDevice.sync()

      assert Repo.reload(own).matched_transaction_id == nil
      assert Repo.reload(c.checking).shared_expenses == false
      assert Repo.reload(c.shared).shared_expenses == true
      SyncDevice.assert_converged(mac, Transaction, own.id)
      SyncDevice.assert_converged(mac, Account, c.checking.id)
      SyncDevice.assert_converged(mac, Account, c.shared.id)
    end
  end

  describe "a led transfer" do
    setup c do
      {:ok, payback} =
        Expenses.create_expense(
          scope_of(c.h.anna),
          reimbursement(3000, "2026-11-02", c.h.anna, c.h.ben),
          budget_account_id: c.checking.id
        )

      shared_side = led(payback)

      %{
        shared_side: shared_side,
        checking_side: Repo.get!(Transaction, shared_side.transfer_transaction_id)
      }
    end

    test "is not deleted, on either side, and its counterpart keeps its fields too", c do
      mac =
        c.scope
        |> SyncDevice.new("mac")
        |> SyncDevice.edit(
          "transactions",
          c.shared_side.id,
          %{deleted_at: "2026-11-02T10:05:00.000000Z"},
          @at
        )
        |> SyncDevice.edit(
          "transactions",
          c.checking_side.id,
          %{date: "2026-11-03", account_id: c.shared.id, cleared: "cleared"},
          @at
        )
        |> SyncDevice.sync()

      assert Repo.reload(c.shared_side).deleted_at == nil

      assert %Transaction{date: ~D[2026-11-02], cleared: :cleared, account_id: checking} =
               Repo.reload(c.checking_side)

      assert checking == c.checking.id
      SyncDevice.assert_converged(mac, Transaction, c.shared_side.id)
      SyncDevice.assert_converged(mac, Transaction, c.checking_side.id)
    end

    test "is not joined by a transaction a device makes its counterpart", c do
      other = transaction_fixture(account_id: c.checking.id, amount: -100)
      created = Ids.generate()

      mac =
        c.scope
        |> SyncDevice.new("mac")
        |> SyncDevice.edit(
          "transactions",
          other.id,
          %{transfer_transaction_id: c.shared_side.id, memo: "Gegenbuchung"},
          @at
        )
        |> SyncDevice.edit(
          "transactions",
          created,
          %{
            account_id: c.checking.id,
            date: "2026-11-02",
            amount: -3000,
            transfer_transaction_id: c.shared_side.id,
            cleared: "uncleared",
            approved: true,
            source: "manual"
          },
          @at
        )
        |> SyncDevice.sync()

      assert %Transaction{transfer_transaction_id: nil, memo: "Gegenbuchung"} = Repo.reload(other)

      assert %Transaction{transfer_transaction_id: nil, amount: -3000} =
               Repo.get!(Transaction, created)

      assert Repo.reload(c.shared_side).transfer_transaction_id == c.checking_side.id
      SyncDevice.assert_converged(mac, Transaction, other.id)
      SyncDevice.assert_converged(mac, Transaction, created)
    end

    test "is not joined by a part a device makes its counterpart", c do
      split =
        transaction_fixture(
          account_id: c.checking.id,
          amount: -1_000,
          subtransactions: [%{amount: -600}, %{amount: -400}]
        )

      [part, _other] = Repo.preload(split, :subtransactions).subtransactions
      created = Ids.generate()

      mac =
        c.scope
        |> SyncDevice.new("mac")
        |> SyncDevice.edit(
          "subtransactions",
          part.id,
          %{transfer_transaction_id: c.shared_side.id, memo: "Gegenbuchung"},
          @at
        )
        |> SyncDevice.edit(
          "subtransactions",
          created,
          %{
            transaction_id: split.id,
            amount: 0,
            position: 2,
            transfer_transaction_id: c.shared_side.id
          },
          @at
        )
        |> SyncDevice.sync()

      assert %Subtransaction{transfer_transaction_id: nil, memo: "Gegenbuchung"} =
               Repo.reload(part)

      assert %Subtransaction{transfer_transaction_id: nil, deleted_at: nil} =
               Repo.get!(Subtransaction, created)

      assert Repo.reload(c.shared_side).transfer_transaction_id == c.checking_side.id
      SyncDevice.assert_converged(mac, Subtransaction, part.id)
      SyncDevice.assert_converged(mac, Subtransaction, created)
    end
  end

  describe "the parts of a led transaction" do
    test "a part a device adds is created and deleted again", c do
      transaction = market(c)
      part = Ids.generate()

      mac =
        c.scope
        |> SyncDevice.new("mac")
        |> SyncDevice.edit(
          "subtransactions",
          part,
          %{transaction_id: transaction.id, amount: -1000, position: 0},
          @at
        )
        |> SyncDevice.sync()

      assert %Subtransaction{deleted_at: %DateTime{}} = Repo.get!(Subtransaction, part)
      SyncDevice.assert_converged(mac, Subtransaction, part)
    end

    test "a part a device moves into one keeps its transaction", c do
      transaction = market(c)

      split =
        transaction_fixture(
          account_id: c.checking.id,
          amount: -1_000,
          subtransactions: [%{amount: -600}, %{amount: -400}]
        )

      [part, _other] = Repo.preload(split, :subtransactions).subtransactions

      mac =
        c.scope
        |> SyncDevice.new("mac")
        |> SyncDevice.edit("subtransactions", part.id, %{transaction_id: transaction.id}, @at)
        |> SyncDevice.sync()

      assert Repo.reload(part).transaction_id == split.id
      SyncDevice.assert_converged(mac, Subtransaction, part.id)
    end
  end
end
