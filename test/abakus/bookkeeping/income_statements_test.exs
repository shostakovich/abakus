defmodule Abakus.Bookkeeping.IncomeStatementsTest do
  use Abakus.DataCase

  import Abakus.BookkeepingFixtures
  import Abakus.DomainFixtures

  alias Abakus.{Bookkeeping, UsersFixtures}
  alias Abakus.Bookkeeping.{FixedAssets, IncomeStatement, IncomeStatements, VatReturn, VatReturns}
  alias Abakus.Users.Scope

  setup do
    %{scope: budget_scope(), account: account_fixture(name: "Kontist", kind: :tracking)}
  end

  defp booked(c, date, amount, category, vat) do
    transaction = transaction_fixture(account_id: c.account.id, date: date, amount: amount)

    {:ok, _lines} =
      Bookkeeping.save_tax_lines(c.scope, Bookkeeping.get_transaction(c.scope, transaction.id), %{
        "transaction" => %{"category" => category, "vat" => vat}
      })

    transaction
  end

  defp kennzahlen(scope, year),
    do: scope |> IncomeStatements.year(year) |> IncomeStatement.kennzahlen()

  test "a low-value asset is expensed at once, a larger one depreciated", c do
    fixed_asset_fixture(c.scope, %{"name" => "Monitor", "net" => "650", "useful_life" => ""})
    fixed_asset_fixture(c.scope, %{"name" => "Notebook", "net" => "2.400", "useful_life" => "3"})

    kz = kennzahlen(c.scope, 2027)

    assert kz[132] == 65_000
    assert kz[130] == 60_000
    assert kennzahlen(c.scope, 2028)[130] == 80_000
    refute Map.has_key?(kennzahlen(c.scope, 2028), 132)
  end

  test "a traded-in asset leaves the register", c do
    asset =
      fixed_asset_fixture(c.scope, %{
        "purchased_on" => "2025-03-01",
        "net" => "900",
        "useful_life" => "3"
      })

    assert kennzahlen(c.scope, 2025)[130] == 25_000
    assert kennzahlen(c.scope, 2026)[130] == 30_000

    disposal_fixture(c.scope, asset, %{
      "kind" => "sale",
      "date" => "2027-01-20",
      "amount" => "238,00",
      "vat" => "19"
    })

    kz = kennzahlen(c.scope, 2027)
    assert kz[130] == 2_500
    assert kz[135] == 32_500
    assert kz[102] == 20_000
    assert kz[140] == 3_800
    assert kennzahlen(c.scope, 2028) == %{159 => 0, 199 => 0}

    assert VatReturn.kennzahlen(VatReturns.quarter(c.scope, 2027, 1))[81] == 200
    assert VatReturns.year(c.scope, 2027) |> VatReturn.kennzahlen() |> Map.get(177) == 200
  end

  test "a year with income, expenses and assets gives its lines", c do
    booked(c, ~D[2027-01-20], 119_000, "revenue", "19")
    booked(c, ~D[2027-02-10], -5_950, "internet", "19")
    booked(c, ~D[2027-03-01], -10_000, "licenses_13b_eu", "reverse_charge")
    booked(c, ~D[2027-03-03], -11_900, "private", "19")
    booked(c, ~D[2027-04-10], -77_350, "low_value_assets", "19")
    booked(c, ~D[2027-04-10], -285_600, "office_equipment", "19")
    booked(c, ~D[2027-05-10], -30_000, "vat_payment", "0")
    booked(c, ~D[2026-12-31], 119_000, "revenue", "19")

    fixed_asset_fixture(c.scope, %{"name" => "Monitor", "net" => "650", "useful_life" => ""})
    fixed_asset_fixture(c.scope, %{"name" => "Notebook", "net" => "2.400", "useful_life" => "3"})

    car =
      fixed_asset_fixture(c.scope, %{
        "name" => "Lastenrad",
        "purchased_on" => "2025-07-01",
        "net" => "3.000",
        "useful_life" => "5"
      })

    disposal_fixture(c.scope, car, %{
      "kind" => "withdrawal",
      "date" => "2027-06-15",
      "amount" => "1.190",
      "vat" => "19"
    })

    assert kennzahlen(c.scope, 2027) == %{
             112 => 100_000,
             140 => 19_000 + 19_000,
             102 => 100_000,
             280 => 5_000,
             183 => 10_000,
             132 => 65_000,
             130 => 60_000 + 30_000,
             135 => 300_000 - 120_000,
             185 => 950 + 12_350 + 45_600,
             186 => 30_000,
             159 => 238_000,
             199 => 5_000 + 10_000 + 65_000 + 90_000 + 180_000 + 58_900 + 30_000
           }
  end

  test "a transaction that pays a disposal counts through the disposal", c do
    payment = booked(c, ~D[2027-01-22], 23_800, "revenue", "19")
    {:ok, _ids} = Bookkeeping.put_business_accounts(c.scope, [c.account.id])

    asset =
      fixed_asset_fixture(c.scope, %{"purchased_on" => "2025-03-01", "net" => "900"})

    disposal_fixture(c.scope, asset, %{"transaction_id" => payment.id})

    kz = kennzahlen(c.scope, 2027)
    refute Map.has_key?(kz, 112)
    assert kz[102] == 20_000
    assert VatReturn.kennzahlen(VatReturns.quarter(c.scope, 2027, 1))[81] == 200

    refute Enum.any?(Bookkeeping.inbox(c.scope), fn {t, missing} ->
             t.id == payment.id and :category in missing
           end)
  end

  test "leaves out other users' assets", c do
    fixed_asset_fixture(c.scope, %{"net" => "650"})
    other = Scope.for_user(UsersFixtures.user_fixture())

    assert kennzahlen(other, 2027) == %{159 => 0, 199 => 0}
    assert FixedAssets.list(other) == []
  end
end
