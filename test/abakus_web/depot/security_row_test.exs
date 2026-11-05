defmodule AbakusWeb.Depot.SecurityRowTest do
  use ExUnit.Case, async: true

  alias Abakus.Depot.Securities.Security
  alias AbakusWeb.Depot.SecurityRow

  @today ~D[2026-11-05]

  defp security(attrs \\ []),
    do:
      struct!(
        %Security{id: 1, quote_feed: :yahoo, symbol: "VGWL.DE", isin: "IE00B3RBWM25"},
        attrs
      )

  test "source/1 names Yahoo with the symbol, or no fetching, retired as well" do
    assert SecurityRow.source(security()) == "Yahoo⁠ · VGWL.DE"
    assert SecurityRow.source(security(quote_feed: :manual)) == "Ohne Kursabruf"
    assert SecurityRow.source(security(retired: true, symbol: "VGEU.F")) == "Yahoo⁠ · VGEU.F"
    assert SecurityRow.source(security(retired: true, quote_feed: :manual)) == "Ohne Kursabruf"
  end

  test "short_source/1 is the symbol alone, else the source" do
    assert SecurityRow.short_source(security()) == "VGWL.DE"
    assert SecurityRow.short_source(security(quote_feed: :manual)) == "Ohne Kursabruf"
    assert SecurityRow.short_source(security(retired: true, symbol: "VGEU.F")) == "VGEU.F"
  end

  test "quote_date/2 leaves the year out in the current one" do
    assert SecurityRow.quote_date(security(latest_date: ~D[2026-11-04]), @today) == "04.11."
    assert SecurityRow.quote_date(security(latest_date: ~D[2024-09-06]), @today) == "06.09.2024"
    assert SecurityRow.quote_date(security(), @today) == nil
  end

  test "price/1 keeps the decimals of each quote, a dash without one" do
    assert SecurityRow.price(security(latest_close: 16_416_000_000, currency: "EUR")) ==
             "164,16\u00A0€"

    assert SecurityRow.price(security(latest_close: 997_250_000, currency: "USD")) ==
             "9,9725\u00A0USD"

    assert SecurityRow.price(security()) == "–"
  end

  describe "marks/3" do
    test "has the errors of Yahoo and DivvyDiary, a missing ISIN and the user's benchmark" do
      failing =
        security(
          id: 7,
          fetch_error: "Yahoo kennt das Symbol VGWL.DE nicht.",
          divvy_diary_error: "DivvyDiary ist nicht erreichbar."
        )

      assert SecurityRow.marks(failing, 7, true) == [
               {:error, "Yahoo kennt das Symbol VGWL.DE nicht."},
               {:error, "DivvyDiary ist nicht erreichbar."},
               :benchmark
             ]

      assert SecurityRow.marks(security(isin: nil), nil, true) == [:no_isin]
      assert SecurityRow.marks(security(), 7, true) == []
    end

    test "DivvyDiary's marks only with its API key" do
      failing = security(divvy_diary_error: "DivvyDiary ist nicht erreichbar.")
      unknown = security(divvy_diary_unknown: true)

      assert SecurityRow.marks(failing, nil, false) == []
      assert SecurityRow.marks(unknown, nil, false) == []
      assert SecurityRow.marks(unknown, nil, true) == [:no_fund_data]
    end

    test "leaves out Yahoo's last error once the prices come from elsewhere" do
      assert SecurityRow.marks(security(quote_feed: :manual, fetch_error: "alt"), nil, true) == []
    end

    test "a retired security fetches nothing, so only the benchmark shows" do
      retired =
        security(
          retired: true,
          isin: nil,
          fetch_error: "alt",
          divvy_diary_error: "alt",
          divvy_diary_unknown: true
        )

      assert SecurityRow.marks(retired, nil, true) == []
      assert SecurityRow.marks(retired, 1, true) == [:benchmark]
    end
  end
end
