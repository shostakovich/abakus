defmodule Abakus.Bookkeeping.VatReturnsTest do
  use Abakus.DataCase

  import Abakus.DomainFixtures

  alias Abakus.{Bookkeeping, Ledger, UsersFixtures}
  alias Abakus.Bookkeeping.{VatReturn, VatReturns}
  alias Abakus.Users.Scope

  setup do
    %{scope: budget_scope(), account: account_fixture(name: "Kontist", kind: :tracking)}
  end

  defp booked(c, date, amount, category, vat) do
    transaction = transaction_fixture(account_id: c.account.id, date: date, amount: amount)
    tax!(c.scope, transaction, %{"transaction" => %{"category" => category, "vat" => vat}})
    transaction
  end

  defp tax!(scope, transaction, params) do
    {:ok, _lines} =
      Bookkeeping.save_tax_lines(
        scope,
        Bookkeeping.get_transaction(scope, transaction.id),
        params
      )
  end

  defp kennzahlen(scope, year, quarter),
    do: scope |> VatReturns.quarter(year, quarter) |> VatReturn.kennzahlen()

  test "reverse charge on a service from abroad leaves the amount due as it is", c do
    booked(c, ~D[2027-01-20], 119_000, "revenue", "19")
    before = kennzahlen(c.scope, 2027, 1)

    booked(c, ~D[2027-02-10], -10_000, "licenses_13b_eu", "reverse_charge")
    kz = kennzahlen(c.scope, 2027, 1)

    assert kz[46] == 100
    assert kz[47] == 1_900
    assert kz[67] == 1_900
    assert kz[83] == before[83]
    assert kz[83] == 19_000
  end

  test "a quarter with 19 %, 7 % and §13b transactions gives its Kennzahlen", c do
    booked(c, ~D[2027-01-20], 119_000, "revenue", "19")
    booked(c, ~D[2027-02-03], 11_999, "other_revenue", "19")
    booked(c, ~D[2027-03-31], 53_500, "revenue", "7")
    booked(c, ~D[2027-01-05], -5_950, "internet", "19")
    booked(c, ~D[2027-02-14], -1_070, "books", "7")
    booked(c, ~D[2027-02-10], -10_000, "licenses_13b_eu", "reverse_charge")
    booked(c, ~D[2027-03-01], -20_000, "training_13b_third_country", "reverse_charge")
    booked(c, ~D[2027-03-02], -2_000, "bank_fees", "0")
    booked(c, ~D[2027-03-03], -11_900, "private", "19")
    booked(c, ~D[2027-04-01], 119_000, "revenue", "19")
    booked(c, ~D[2026-12-31], -5_950, "internet", "19")

    assert kennzahlen(c.scope, 2027, 1) == %{
             81 => 1_100,
             86 => 500,
             46 => 100,
             47 => 1_900,
             84 => 200,
             85 => 3_800,
             66 => 950 + 70,
             67 => 1_900 + 3_800,
             83 => 1_100 * 19 + 500 * 7 + 1_900 + 3_800 - 1_020 - 5_700
           }
  end

  test "counts each part of a split by its own amount on the transaction's date", c do
    {:ok, split} =
      Ledger.create_transaction(c.scope, %{
        account_id: c.account.id,
        date: ~D[2027-05-02],
        amount: 119_000 - 11_900,
        subtransactions: [%{amount: 119_000}, %{amount: -11_900}]
      })

    [sale, purchase] = Bookkeeping.get_transaction(c.scope, split.id).subtransactions

    tax!(c.scope, split, %{
      sale.id => %{"category" => "revenue", "vat" => "19"},
      purchase.id => %{"category" => "office_supplies", "vat" => "19"}
    })

    assert %{81 => 1_000, 66 => 1_900, 83 => 17_100} = kennzahlen(c.scope, 2027, 2)
  end

  test "puts other rates under 35 and 36", c do
    booked(c, ~D[2020-08-03], 11_600, "revenue", "16")
    booked(c, ~D[2020-09-01], 10_500, "revenue", "5")

    assert kennzahlen(c.scope, 2020, 3) == %{35 => 200, 36 => 2_100, 83 => 2_100}
  end

  test "leaves out deleted transactions and other users' tax lines", c do
    deleted = booked(c, ~D[2027-01-20], 119_000, "revenue", "19")
    {:ok, _deleted} = Ledger.delete_transaction(c.scope, deleted)

    other = Scope.for_user(UsersFixtures.user_fixture())
    {:ok, account} = Ledger.create_account(other, %{name: "Fremd", kind: :checking})

    {:ok, theirs} =
      Ledger.create_transaction(other, %{
        account_id: account.id,
        date: ~D[2027-01-20],
        amount: 119_000
      })

    tax!(other, theirs, %{"transaction" => %{"category" => "revenue", "vat" => "19"}})

    assert kennzahlen(c.scope, 2027, 1) == %{83 => 0}
    assert kennzahlen(other, 2027, 1)[81] == 1_000
  end

  test "the annual return rounds the year's bases and owes what the quarters left", c do
    booked(c, ~D[2027-02-01], 11_999, "revenue", "19")
    booked(c, ~D[2027-05-01], 11_999, "revenue", "19")
    booked(c, ~D[2027-06-01], -10_000, "licenses_13b_eu", "reverse_charge")
    booked(c, ~D[2027-11-01], -5_950, "internet", "19")

    annual = VatReturns.year(c.scope, 2027)

    assert annual.prepaid == 1_900 + 1_900 - 950
    assert annual.balance == 201 * 19 - 950 - annual.prepaid

    assert VatReturn.kennzahlen(annual) == %{
             177 => 201,
             846 => 100,
             847 => 1_900,
             320 => 950,
             467 => 1_900,
             816 => 201 * 19 - 950,
             820 => 19
           }
  end
end
