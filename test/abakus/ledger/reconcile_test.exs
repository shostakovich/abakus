defmodule Abakus.Ledger.ReconcileTest do
  use Abakus.DataCase

  import Abakus.DomainFixtures

  alias Abakus.{Categories, Ledger}
  alias Abakus.Ledger.{Account, BankBalance, Transaction}

  @today ~D[2026-10-10]

  setup do
    %{giro: account_fixture(kind: :checking), depot: account_fixture(kind: :tracking)}
  end

  defp reload(%{id: id}), do: Repo.get!(Transaction, id)

  defp cleared(attrs), do: transaction_fixture(Enum.into(attrs, %{cleared: :cleared}))

  defp balance(account), do: Map.fetch!(Ledger.balances(), account.id)

  defp today(amount), do: %{amount: amount, date: @today, through: @today}

  describe "latest_bank_balance/1" do
    test "is the newest of any source, nil without one", %{giro: giro} do
      assert Ledger.latest_bank_balance(giro) == nil

      Ledger.put_bank_balance(giro, %{amount: 1, date: ~D[2026-10-07], source: :file})
      Ledger.put_bank_balance(giro, %{amount: 2, date: ~D[2026-10-08], source: :file})
      Ledger.put_bank_balance(giro, %{amount: 3, date: ~D[2026-10-06], source: :bank})

      Ledger.put_bank_balance(account_fixture(), %{
        amount: 4,
        date: ~D[2026-10-09],
        source: :file
      })

      assert %BankBalance{amount: 2, date: ~D[2026-10-08]} = Ledger.latest_bank_balance(giro)
    end
  end

  describe "cleared_balance/2" do
    test "adds up the cleared and reconciled register up to a date", %{giro: giro} do
      cleared(account_id: giro.id, date: ~D[2026-10-08], amount: 10_000)
      cleared(account_id: giro.id, date: ~D[2026-10-09], amount: 500)

      transaction_fixture(
        account_id: giro.id,
        date: ~D[2026-10-01],
        cleared: :reconciled,
        amount: 2_000
      )

      transaction_fixture(account_id: giro.id, date: ~D[2026-10-08], amount: -700)
      deleted = cleared(account_id: giro.id, date: ~D[2026-10-08], amount: 99)
      {:ok, _} = Ledger.delete_transaction(deleted)
      cleared(account_id: account_fixture().id)

      assert Ledger.cleared_balance(giro, ~D[2026-10-09]) == 12_500
      assert Ledger.cleared_balance(giro, ~D[2026-10-08]) == 12_000
      assert Ledger.cleared_balance(account_fixture(), @today) == 0
    end
  end

  describe "reconcile/3" do
    test "a bank balance counts up to its date", %{giro: giro} do
      # Scenario: A file balance counts up to its date
      early = cleared(account_id: giro.id, date: ~D[2026-10-01], amount: 20_000)
      due = cleared(account_id: giro.id, date: ~D[2026-10-08], amount: -6_752)
      later = cleared(account_id: giro.id, date: ~D[2026-10-09], amount: -1_000)
      open = transaction_fixture(account_id: giro.id, date: ~D[2026-10-05], amount: -300)

      assert {:ok, %{reconciled: 2, adjustment: nil}} =
               Ledger.reconcile(giro, %{
                 amount: 13_248,
                 date: ~D[2026-10-08],
                 through: ~D[2026-10-08]
               })

      assert Enum.map([early, due, later, open], &reload(&1).cleared) ==
               [:reconciled, :reconciled, :cleared, :uncleared]

      # The balance equation holds: 132,48 − 10,00 cleared, −3,00 uncleared.
      assert %{cleared: 12_248, uncleared: -300, balance: 11_948} = balance(giro)
    end

    test "a balance as of today leaves later cleared transactions alone", %{giro: giro} do
      # Scenario: A balance entered by hand counts as of today
      first = cleared(account_id: giro.id, date: ~D[2026-10-01], amount: 10_000)
      second = cleared(account_id: giro.id, date: @today, amount: 5_000)
      future = cleared(account_id: giro.id, date: ~D[2026-11-01], amount: 700)

      assert {:ok, %{reconciled: 2, adjustment: nil}} = Ledger.reconcile(giro, today(15_000))

      assert Enum.map([first, second, future], &reload(&1).cleared) ==
               [:reconciled, :reconciled, :cleared]

      assert Ledger.last_reconciled_date(giro) == @today
    end

    test "locks approved transactions only, and none an open match proposal waits for", %{
      giro: giro
    } do
      approved = cleared(account_id: giro.id, amount: 300)
      unapproved = cleared(account_id: giro.id, amount: 1_000, source: :file)
      matched = cleared(account_id: giro.id, amount: 500)

      {:ok, proposal} =
        Ledger.create_transaction(%{
          account_id: giro.id,
          date: matched.date,
          amount: 500,
          cleared: :cleared,
          source: :file,
          matched_transaction_id: matched.id
        })

      deleted = cleared(account_id: giro.id, amount: 77)
      {:ok, _} = Ledger.delete_transaction(deleted)

      assert {:ok, %{reconciled: 1}} = Ledger.reconcile(giro, today(1_800))

      assert Enum.map([approved, unapproved, matched, proposal, deleted], &reload(&1).cleared) ==
               [:reconciled, :cleared, :cleared, :cleared, :cleared]

      assert {:ok, %Transaction{id: id}} = Ledger.accept_match(proposal)
      assert id == matched.id
    end

    test "leaves other accounts alone and sets when the account was reconciled", %{giro: giro} do
      other = account_fixture()
      elsewhere = cleared(account_id: other.id, amount: 1_000)

      assert {:ok, _} = Ledger.reconcile(giro, today(0))

      assert reload(elsewhere).cleared == :cleared
      assert %DateTime{} = Repo.get!(Account, giro.id).last_reconciled_at
      assert Repo.get!(Account, other.id).last_reconciled_at == nil
    end

    test "refuses a difference other than the one expected and changes nothing", %{giro: giro} do
      transaction = cleared(account_id: giro.id, amount: 1_000)

      assert {:error, {:difference, 42}} = Ledger.reconcile(giro, today(1_042))
      assert {:error, {:difference, 42}} = Ledger.reconcile(giro, today(1_042), adjust: 40)
      assert {:error, {:difference, 0}} = Ledger.reconcile(giro, today(1_000), adjust: 42)

      assert reload(transaction).cleared == :cleared
      assert Repo.aggregate(Transaction, :count) == 1
      assert Repo.get!(Account, giro.id).last_reconciled_at == nil
    end

    test "books the expected difference as an approved, reconciled adjustment to Ready to Assign",
         %{giro: giro} do
      # Scenario: A difference becomes an adjustment
      transaction = cleared(account_id: giro.id, date: ~D[2026-10-01], amount: 1_000)
      open = transaction_fixture(account_id: giro.id, date: ~D[2026-10-02], amount: -250)

      assert {:ok, %{reconciled: 2, adjustment: %Transaction{} = adjustment}} =
               Ledger.reconcile(
                 giro,
                 %{amount: 1_042, date: ~D[2026-10-08], through: ~D[2026-10-08]},
                 adjust: 42
               )

      adjustment = adjustment |> reload() |> Repo.preload(:payee)

      assert %Transaction{
               amount: 42,
               date: ~D[2026-10-08],
               cleared: :reconciled,
               approved: true,
               source: :manual,
               memo: "Beim Abgleichen automatisch angelegt"
             } = adjustment

      assert adjustment.payee.name == "Ausgleichsbuchung"
      assert adjustment.category_id == Categories.ready_to_assign!().id
      assert reload(transaction).cleared == :reconciled
      assert reload(open).cleared == :uncleared
      assert Ledger.cleared_balance(giro, ~D[2026-10-08]) == 1_042
      assert %{cleared: 1_042, uncleared: -250, balance: 792} = balance(giro)
    end

    test "a negative difference books an outflow", %{giro: giro} do
      cleared(account_id: giro.id, amount: 1_000)

      assert {:ok, %{adjustment: %Transaction{amount: -1_200}}} =
               Ledger.reconcile(giro, today(-200), adjust: -1_200)

      assert %{cleared: -200, balance: -200} = balance(giro)
    end

    test "an adjustment in a tracking account has no category", %{depot: depot} do
      assert {:ok, %{adjustment: adjustment}} =
               Ledger.reconcile(depot, today(5_000), adjust: 5_000)

      assert %Transaction{amount: 5_000, category_id: nil, cleared: :reconciled} =
               reload(adjustment)
    end

    test "reconciles accounts fed by another app too" do
      fed = account_fixture(kind: :checking, fed_by: :shared_expenses)
      cleared(account_id: fed.id, amount: 1_000)

      assert {:ok, %{reconciled: 2, adjustment: %Transaction{amount: 1}}} =
               Ledger.reconcile(fed, today(1_001), adjust: 1)
    end
  end
end
