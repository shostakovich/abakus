defmodule Abakus.Bookkeeping.VatReturnTest do
  use ExUnit.Case, async: true

  alias Abakus.Bookkeeping.{Category, VatReturn}

  defp entry(category, vat, amount, date \\ ~D[2027-02-01]),
    do: %{date: date, category: Category.get(category), vat: vat, amount: amount}

  test "rounds a base down in the owner's favour, also below zero" do
    sale = entry("revenue", :rate_19, 11_999)
    credit = entry("revenue", :rate_19, -11_999)

    assert VatReturn.kennzahlen(VatReturn.quarter(2027, 1, [sale])) == %{81 => 100, 83 => 1_900}

    assert VatReturn.kennzahlen(VatReturn.quarter(2027, 1, [credit])) ==
             %{81 => -101, 83 => -1_919}
  end

  test "a refund of an expense lowers the input VAT" do
    purchase = entry("internet", :rate_19, -5_950)
    refund = entry("internet", :rate_19, 1_190)

    assert VatReturn.kennzahlen(VatReturn.quarter(2027, 1, [purchase, refund])) ==
             %{66 => 760, 83 => -760}
  end

  test "income at 0 % and private bookings count for none" do
    entries = [entry("other_revenue", :rate_0, 50_000), entry("private", :rate_19, -11_900)]

    assert VatReturn.kennzahlen(VatReturn.quarter(2027, 1, entries)) == %{83 => 0}
  end

  test "spans a quarter from its first to its last day" do
    assert VatReturn.quarter_span(2027, 1) == {~D[2027-01-01], ~D[2027-03-31]}
    assert VatReturn.quarter_span(2028, 4) == {~D[2028-10-01], ~D[2028-12-31]}
  end
end
