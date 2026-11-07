defmodule Abakus.Bookkeeping.DepreciationTest do
  use ExUnit.Case, async: true

  alias Abakus.Bookkeeping.{Depreciation, Disposal, FixedAsset}

  defp asset(purchased_on, net, useful_life, disposal \\ nil),
    do: %FixedAsset{
      purchased_on: purchased_on,
      net: net,
      useful_life: useful_life,
      disposal: disposal
    }

  defp write_offs(asset, years), do: Enum.map(years, &Depreciation.year(asset, &1).write_off)

  test "expenses up to 800 € net at once in the purchase year" do
    gwg = asset(~D[2027-12-31], 80_000, nil)

    assert write_offs(gwg, 2026..2028) == [0, 80_000, 0]
    assert Depreciation.year(gwg, 2027).low_value?
    refute Depreciation.year(asset(~D[2027-12-31], 80_001, 1), 2027).low_value?
  end

  test "depreciates by month from the month of purchase, the years adding up to the cent" do
    notebook = asset(~D[2027-04-30], 100_000, 3)

    assert write_offs(notebook, 2027..2031) == [25_000, 33_333, 33_334, 8_333, 0]
    assert Enum.sum(write_offs(notebook, 2027..2031)) == 100_000
    assert Depreciation.book_value(notebook, ~D[2027-04-01]) == 100_000 - 2_778
  end

  test "depreciates up to and including the month of the disposal and leaves its book value" do
    disposal = %Disposal{kind: :sale, date: ~D[2027-01-20], amount: 23_800, vat: :rate_19}
    bike = asset(~D[2025-03-01], 90_000, 3, disposal)

    assert write_offs(bike, 2025..2028) == [25_000, 30_000, 2_500, 0]
    assert %{disposal: ^disposal, remaining: 32_500} = Depreciation.year(bike, 2027)
    assert %{disposal: nil, remaining: 0} = Depreciation.year(bike, 2026)
    assert Depreciation.current_value(bike, ~D[2027-01-19]) == 32_500
    assert Depreciation.current_value(bike, ~D[2027-01-20]) == 0
  end

  test "a low-value asset leaves no book value" do
    disposal = %Disposal{kind: :withdrawal, date: ~D[2027-08-01], amount: 0, vat: :rate_0}
    assert Depreciation.year(asset(~D[2027-04-10], 65_000, nil, disposal), 2027).remaining == 0
  end
end
