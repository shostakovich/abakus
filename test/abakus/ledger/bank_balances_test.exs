defmodule Abakus.Ledger.BankBalancesTest do
  use Abakus.DataCase

  import Abakus.DomainFixtures

  alias Abakus.Ledger
  alias Abakus.Ledger.BankBalance

  test "records what the bank reports per account, source and date" do
    account = account_fixture()

    assert {:ok, %BankBalance{amount: 242_323, date: ~D[2026-09-30], source: :file}} =
             Ledger.put_bank_balance(account, %{
               amount: 242_323,
               date: ~D[2026-09-30],
               source: :file
             })

    {:ok, _balance} =
      Ledger.put_bank_balance(account, %{amount: 241_613, date: ~D[2026-10-07], source: :file})

    {:ok, _balance} =
      Ledger.put_bank_balance(account, %{amount: 1, date: ~D[2026-10-07], source: :bank})

    assert Repo.aggregate(BankBalance, :count) == 3
  end

  test "a second one for the same source and date replaces the first" do
    account = account_fixture()

    {:ok, _balance} =
      Ledger.put_bank_balance(account, %{amount: 1, date: ~D[2026-10-07], source: :file})

    assert {:ok, %BankBalance{amount: 2}} =
             Ledger.put_bank_balance(account, %{amount: 2, date: ~D[2026-10-07], source: :file})

    assert [%BankBalance{amount: 2}] = Repo.all(BankBalance)
  end

  test "refuses a balance without amount, date or a known source, and amounts out of range" do
    account = account_fixture()

    assert {:error, changeset} = Ledger.put_bank_balance(account, %{source: :manual})
    assert %{amount: [_], date: [_], source: [_]} = errors_on(changeset)

    assert {:error, changeset} =
             Ledger.put_bank_balance(account, %{
               amount: 10_000_000_000_001,
               date: ~D[2026-10-07],
               source: :file
             })

    assert %{amount: [_]} = errors_on(changeset)
  end
end
