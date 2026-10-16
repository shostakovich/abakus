defmodule Abakus.Depot.MarketData.YahooTest do
  use ExUnit.Case, async: true

  alias Abakus.Depot.MarketData.Yahoo

  @body File.read!("test/fixtures/depot/yahoo/chart.json")

  # 2026-10-09 is still trading in the fixture until 17:30 CEST.
  @during_trading ~U[2026-10-09 10:00:00Z]
  @after_close ~U[2026-10-09 16:00:00Z]

  test "reads the currency, the closes per trading day and the latest quote" do
    assert {:ok, chart} = Yahoo.parse(@body, @after_close)

    assert chart.currency == "EUR"
    assert chart.name == "Vanguard FTSE All-World UCITS ETF"

    assert chart.closes == [
             {~D[2026-10-05], 16_704_000_000},
             {~D[2026-10-06], 16_768_000_000},
             {~D[2026-10-07], 16_702_000_000},
             {~D[2026-10-09], 16_666_000_000}
           ]

    assert chart.quote == %{
             at: ~U[2026-10-09 08:23:24.000000Z],
             date: ~D[2026-10-09],
             close: 16_666_000_000
           }
  end

  test "takes the short name without a long one, and no name without either" do
    meta = ["chart", "result", Access.at(0), "meta"]
    decoded = JSON.decode!(@body)
    short_only = decoded |> update_in(meta, &Map.delete(&1, "longName")) |> JSON.encode!()
    nameless = decoded |> update_in(meta, &Map.drop(&1, ~w(longName shortName))) |> JSON.encode!()

    assert {:ok, %{name: "VANGUARD FTSE AW"}} = Yahoo.parse(short_only, @after_close)
    assert {:ok, %{name: nil}} = Yahoo.parse(nameless, @after_close)
  end

  test "names pence and cents as ISO 4217 does" do
    for {yahoo, iso} <- [{"GBp", "GBX"}, {"ZAc", "ZAC"}, {"ILA", "ILA"}, {"GBP", "GBP"}] do
      body =
        @body
        |> JSON.decode!()
        |> put_in(["chart", "result", Access.at(0), "meta", "currency"], yahoo)
        |> JSON.encode!()

      assert {:ok, %{currency: ^iso}} = Yahoo.parse(body, @after_close)
    end
  end

  test "leaves out closes of 0" do
    body =
      @body
      |> JSON.decode!()
      |> update_in(
        ["chart", "result", Access.at(0), "indicators", "quote", Access.at(0), "close"],
        fn [_, _ | rest] -> [0, 0.0 | rest] end
      )
      |> JSON.encode!()

    assert {:ok, %{closes: closes}} = Yahoo.parse(body, @after_close)
    assert Enum.map(closes, &elem(&1, 0)) == [~D[2026-10-07], ~D[2026-10-09]]
  end

  test "leaves out the day that is still trading" do
    assert {:ok, chart} = Yahoo.parse(@body, @during_trading)

    assert List.last(chart.closes) == {~D[2026-10-07], 16_702_000_000}
  end

  test "a range without trading days has no closes" do
    body =
      @body
      |> JSON.decode!()
      |> update_in(["chart", "result", Access.at(0)], &Map.drop(&1, ["timestamp"]))
      |> update_in(
        ["chart", "result", Access.at(0), "indicators", "quote", Access.at(0)],
        &Map.delete(&1, "close")
      )
      |> JSON.encode!()

    assert {:ok, %{closes: []}} = Yahoo.parse(body, @after_close)
  end

  test "a candle at local midnight keeps its day across daylight saving time" do
    # 2026-07-15 00:00 CEST, read with the winter offset of a response from January.
    midnight = DateTime.to_unix(~U[2026-07-14 22:00:00Z])

    body =
      @body
      |> JSON.decode!()
      |> put_in(["chart", "result", Access.at(0), "timestamp"], [midnight])
      |> put_in(["chart", "result", Access.at(0), "meta", "gmtoffset"], 3600)
      |> put_in(["chart", "result", Access.at(0), "indicators", "quote", Access.at(0), "close"], [
        1.5
      ])
      |> JSON.encode!()

    assert {:ok, %{closes: [{~D[2026-07-15], 150_000_000}]}} = Yahoo.parse(body, @after_close)
  end

  test "an unexpected body is reported as such" do
    assert Yahoo.parse("<html>", @after_close) == {:error, :invalid_response}

    assert Yahoo.parse(~s({"chart": {"result": null}}), @after_close) ==
             {:error, :invalid_response}
  end

  describe "parse_search/1" do
    test "reads the listings in Yahoo's order with the long name, else the short one" do
      assert {:ok, listings} =
               Yahoo.parse_search(File.read!("test/fixtures/depot/yahoo/search.json"))

      assert listings == [
               %{symbol: "VWRL.L", name: "Vanguard FTSE All-World UCITS ETF", exchange: "LSE"},
               %{symbol: "VGWL.DE", name: "Vanguard FTSE All-World UCITS ETF", exchange: "GER"},
               %{symbol: "VWRL.AS", name: "VANGUARD FTSE AW", exchange: "AMS"}
             ]
    end

    test "refuses an unexpected body" do
      assert Yahoo.parse_search("<html>") == {:error, :invalid_response}
      assert Yahoo.parse_search(~s({"finance": {}})) == {:error, :invalid_response}
    end
  end
end
