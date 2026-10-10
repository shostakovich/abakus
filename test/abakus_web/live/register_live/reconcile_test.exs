defmodule AbakusWeb.RegisterLive.ReconcileTest do
  use ExUnit.Case, async: true

  alias Abakus.Ledger.{BankBalance, Transaction}
  alias AbakusWeb.RegisterLive.Reconcile

  @today ~D[2026-10-10]

  test "a bank balance counts up to its date" do
    bank = %BankBalance{amount: 13_248, date: ~D[2026-10-08], source: :file}

    assert Reconcile.bank(bank) ==
             %{amount: 13_248, date: ~D[2026-10-08], through: ~D[2026-10-08], source: :file}
  end

  test "a balance entered by hand counts up to today" do
    assert Reconcile.entered("1.234,56", @today) ==
             {:ok, %{amount: 123_456, date: @today, through: @today, source: :entered}}

    assert {:ok, %{amount: -500}} = Reconcile.entered("−5", @today)
    assert {:ok, %{amount: 0}} = Reconcile.entered("0", @today)
  end

  test "a blank or unreadable balance is refused" do
    assert {:error, "Betrag ist ungültig" <> _} = Reconcile.entered("  ", @today)
    assert {:error, _} = Reconcile.entered("zwölf", @today)
    assert {:error, _} = Reconcile.entered("1,234", @today)
    assert {:error, _} = Reconcile.entered(%{"a" => "1"}, @today)
    assert {:error, _} = Reconcile.entered(["1"], @today)
  end

  test "a balance beyond the amounts' range is refused" do
    assert {:ok, %{amount: 10_000_000_000_000}} = Reconcile.entered("100000000000", @today)
    assert {:error, "Betrag muss zwischen" <> _} = Reconcile.entered("100000000000,01", @today)
  end

  test "the difference is what the bank has more" do
    assert Reconcile.difference(%{bank: %{amount: 15_042}, cleared: 15_000}) == 42
    assert Reconcile.difference(%{bank: %{amount: 14_000}, cleared: 15_000}) == -1_000
  end

  test "says how many transactions were locked and what was adjusted" do
    assert Reconcile.done_text(%{reconciled: 0, adjustment: nil}) == "Abgeglichen."

    assert Reconcile.done_text(%{reconciled: 1, adjustment: nil}) ==
             "Abgeglichen, 1 Buchung abgeschlossen."

    assert Reconcile.done_text(%{reconciled: 3, adjustment: %Transaction{amount: 42}}) ==
             "Ausgleichsbuchung über +0,42 € angelegt, 3 Buchungen abgeschlossen."

    assert Reconcile.refused_text(-500) ==
             "Nicht abgeglichen: Der Saldo weicht inzwischen um −5,00 € ab."
  end
end
