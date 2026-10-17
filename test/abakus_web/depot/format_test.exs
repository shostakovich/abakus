defmodule AbakusWeb.Depot.FormatTest do
  use ExUnit.Case, async: true

  alias AbakusWeb.Depot.Format

  test "prices have two to four decimal places, German separators and a currency that never wraps" do
    assert Format.price(16_666_000_000, "EUR") == "166,66\u00A0€"
    assert Format.price(16_600_000_000, "EUR") == "166,00\u00A0€"
    assert Format.price(123_456_780_000, "USD") == "1.234,5678\u00A0USD"
    assert Format.price(123_456_789_999, "USD") == "1.234,5679\u00A0USD"
    assert Format.price(100_000_000_000_000, nil) == "1.000.000,00"
    assert Format.price(nil, "EUR") == "–"
  end

  test "a portfolio without a name is „Ohne Namen“" do
    assert Format.portfolio_name(%{name: "Sparplan"}) == "Sparplan"
    assert Format.portfolio_name(%{name: ""}) == "Ohne Namen"
    assert Format.portfolio_name(nil) == "Ohne Namen"
  end

  test "currencies are € for euros, otherwise their code" do
    assert Format.currency("EUR") == "€"
    assert Format.currency("USD") == "USD"
  end

  test "prices in a column share the places of the most precise" do
    places = Enum.max(Enum.map([21_400_000, 19_000_000, 37_410_000], &Format.price_places/1))

    assert places == 4
    assert Format.price(19_000_000, "EUR", places) == "0,1900\u00A0€"
    assert Format.price(nil, "EUR", places) == "–"
  end

  test "changes in prices carry their sign and a real minus" do
    assert Format.signed_price(106_000_000, "EUR") == "+1,06\u00A0€"
    assert Format.signed_price(-106_000_000, "USD") == "−1,06\u00A0USD"
    assert Format.signed_price(0, "EUR") == "0,00\u00A0€"
  end

  test "a change in price that rounds to zero has no sign" do
    assert Format.signed_price(153, "EUR") == "0,00\u00A0€"
    assert Format.signed_price(-4_999, "EUR") == "0,00\u00A0€"
    assert Format.signed_price(5_000, "EUR") == "+0,0001\u00A0€"
  end

  test "fund sizes are in billions with one decimal place, below 100 million in millions" do
    assert Format.fund_size(1_784_999_999_999, "EUR") == "17,8\u00A0Mrd.\u00A0\u20AC"
    assert Format.fund_size(40_000_000_000, "EUR") == "0,4\u00A0Mrd.\u00A0\u20AC"
    assert Format.fund_size(10_000_000_000, "USD") == "0,1\u00A0Mrd.\u00A0USD"
    assert Format.fund_size(9_949_999_999, "EUR") == "99\u00A0Mio.\u00A0\u20AC"
    assert Format.fund_size(nil, "EUR") == "\u2013"
  end

  test "a TER, a fraction, is in percent with two decimal places" do
    assert Format.ter(Decimal.new("0.0022")) == "0,22\u00A0%"
    assert Format.ter(Decimal.new("0.012345")) == "1,23\u00A0%"
    assert Format.ter(nil) == "\u2013"
  end
end
