defmodule AbakusWeb.Depot.AttributeValueTest do
  use ExUnit.Case, async: true

  alias Abakus.Depot.Securities.AttributeType
  alias AbakusWeb.Depot.AttributeValue

  defp display(converter, value, currency \\ "EUR") do
    type = %AttributeType{converter: "name.abuchen.portfolio.model.AttributeType$" <> converter}
    AttributeValue.display(type, value, currency)
  end

  test "text is shown as it is" do
    assert display("StringConverter", "Vanguard") == {:text, "Vanguard"}
  end

  test "a percentage is a fraction, a plain one in percent already" do
    assert display("PercentConverter", 0.0025) == {:text, "0,25 %"}
    assert display("PercentConverter", 0) == {:text, "0,00 %"}
    assert display("PercentPlainConverter", 12.5) == {:text, "12,50 %"}
  end

  test "amounts are in cents without a currency, quotes and limits in the security's" do
    assert display("AmountConverter", 123_456) == {:text, "1.234,56"}
    assert display("AmountPlainConverter", 5_000) == {:text, "50,00"}
    assert display("QuoteConverter", 15_012_500_000, "USD") == {:text, "150,125\u00A0USD"}
    assert display("LimitPriceConverter", ">=15000000000") == {:text, "≥ 150,00\u00A0€"}
    assert display("LimitPriceConverter", "<9000000000") == {:text, "< 90,00\u00A0€"}
  end

  test "shares, dates and yes or no" do
    assert display("ShareConverter", 1_250_000_000) == {:text, "12,5"}

    assert display("DateConverter", Date.diff(~D[2012-05-22], ~D[1970-01-01])) ==
             {:text, "22.05.2012"}

    assert display("BooleanConverter", true) == {:text, "ja"}
    assert display("BooleanConverter", false) == {:text, "nein"}
  end

  test "a bookmark is a link with its label, but only to a web address" do
    assert display("BookmarkConverter", "[Factsheet](https://example.com/fs.pdf)") ==
             {:link, "Factsheet", "https://example.com/fs.pdf"}

    assert display("BookmarkConverter", "https://example.com") ==
             {:link, "https://example.com", "https://example.com"}

    assert display("BookmarkConverter", "[]( https://example.com)") ==
             {:text, "[]( https://example.com)"}

    assert display("BookmarkConverter", "[Klick](javascript:alert(1))") ==
             {:text, "[Klick](javascript:alert(1))"}
  end

  test "a logo is shown only as an embedded image" do
    assert display("ImageConverter", "data:image/png;base64,AAAA") ==
             {:image, "data:image/png;base64,AAAA"}

    assert display("ImageConverter", "/home/logo.png") == nil
  end

  test "a value that does not fit its converter is shown as it is, or not at all" do
    assert display("PercentConverter", "0,2 %") == {:text, "0,2 %"}
    assert display("DateConverter", %{"a" => 1}) == nil
    assert display("UnknownConverter", 12) == {:text, "12"}
    assert AttributeValue.display(%AttributeType{}, true, "€") == {:text, "ja"}
  end
end
