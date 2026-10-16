defmodule Abakus.Depot.MarketData.DivvyDiaryTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias Abakus.Depot.MarketData.DivvyDiary
  alias Abakus.Depot.MarketData.DivvyDiary.Response

  # Written by hand: the format is assumed, see the moduledoc of `Response`.
  @json "test/fixtures/depot/divvydiary/symbol.json" |> File.read!() |> JSON.decode!()

  describe "Response.composition/1" do
    test "reads the weights per country and per sector" do
      assert {:ok, %{countries: countries, sectors: sectors}} = Response.composition(@json)

      assert countries == %{
               "US" => 0.5,
               "JP" => 0.1,
               "GB" => 0.1,
               "CA" => 0.05,
               "AU" => 0.05,
               "CN" => 0.1,
               "BR" => 0.1
             }

      assert map_size(sectors) == 7
      assert sectors["Information Technology"] == 0.25
    end

    test "reads weights given as a map, and adds up a country listed twice" do
      json = %{
        "countryWeightings" => [
          %{"country" => "US", "weight" => 0.5},
          %{"country" => "US", "weight" => 0.25},
          %{"country" => "JP", "weight" => 0.25}
        ],
        "sectorWeightings" => %{"Energy" => 1}
      }

      assert Response.composition(json) ==
               {:ok, %{countries: %{"US" => 0.75, "JP" => 0.25}, sectors: %{"Energy" => 1}}}
    end

    test "a share without weightings has no composition" do
      json = %{
        "country" => "DE",
        "sector" => "Health Care",
        "countryWeightings" => [],
        "sectorWeightings" => nil
      }

      assert Response.composition(json) == {:ok, %{countries: %{}, sectors: %{}}}
    end

    test "an answer of another shape is invalid, so the stored composition stays" do
      for json <- [
            %{"countries" => [], "sectors" => []},
            Map.put(@json, "countryWeightings", [%{"name" => "US", "weight" => 1}]),
            Map.put(@json, "countryWeightings", [%{"country" => "US", "weight" => "1"}]),
            Map.put(@json, "sectorWeightings", ["Energy"]),
            Map.put(@json, "sectorWeightings", "mixed"),
            []
          ] do
        assert Response.composition(json) == {:error, :invalid_response}
      end
    end
  end

  describe "Response.symbol/1" do
    test "reads the composition and the dividends, without those marked as forecast" do
      assert {:ok, %{composition: %{countries: %{"US" => 0.5}}, dividends: dividends}} =
               Response.symbol(@json)

      assert dividends == [
               %{
                 ex_date: ~D[2026-09-10],
                 pay_date: ~D[2026-09-24],
                 per_share: 20_000_000,
                 currency: "USD"
               },
               %{
                 ex_date: ~D[2026-06-11],
                 pay_date: ~D[2026-06-24],
                 per_share: 31_250_000,
                 currency: "USD"
               },
               %{
                 ex_date: ~D[2026-03-12],
                 pay_date: ~D[2026-03-25],
                 per_share: 15_000_000,
                 currency: "USD"
               }
             ]
    end

    test "keeps an amount per share to eight places; a whole amount is read too" do
      json =
        Map.put(@json, "dividends", [
          %{
            "exDate" => "2024-02-21",
            "payDate" => "2024-03-07",
            "amount" => 0.5579,
            "currency" => "EUR"
          },
          %{"exDate" => nil, "payDate" => "2024-06-07", "amount" => 1, "currency" => "EUR"}
        ])

      assert {:ok, %{dividends: [first, second]}} = Response.symbol(json)
      assert first.per_share == 55_790_000
      assert {second.ex_date, second.per_share} == {nil, 100_000_000}
    end

    test "leaves out a dividend without a pay date; missing or null dividends are none" do
      without_pay_date = %{
        "exDate" => "2026-12-10",
        "payDate" => nil,
        "amount" => 0.1,
        "currency" => "USD"
      }

      assert {:ok, %{dividends: []}} =
               Response.symbol(Map.put(@json, "dividends", [without_pay_date]))

      assert {:ok, %{dividends: []}} = Response.symbol(Map.put(@json, "dividends", nil))
      assert {:ok, %{dividends: []}} = Response.symbol(Map.delete(@json, "dividends"))
    end

    test "leaves out a dividend of another shape with a warning, and keeps the others" do
      dividend = %{
        "exDate" => "2026-09-10",
        "payDate" => "2026-09-24",
        "amount" => 0.2,
        "currency" => "USD"
      }

      for malformed <- [
            Map.put(dividend, "amount", "0.2"),
            Map.put(dividend, "amount", nil),
            Map.put(dividend, "amount", 0),
            Map.put(dividend, "amount", -0.2),
            Map.put(dividend, "payDate", "24.09.2026"),
            Map.put(dividend, "exDate", 20_260_910),
            Map.delete(dividend, "currency"),
            "dividend"
          ] do
        json = Map.put(@json, "dividends", [malformed, dividend])

        log =
          capture_log(fn ->
            assert {:ok, %{composition: %{countries: %{"US" => 0.5}}, dividends: [read]}} =
                     Response.symbol(json)

            assert read.pay_date == ~D[2026-09-24]
          end)

        assert log =~ "malformed DivvyDiary dividend"
      end
    end

    test "leaves out a dividend marked as forecast in any way" do
      dividend = %{"payDate" => "2026-09-24", "amount" => 0.2, "currency" => "USD"}

      for mark <- [true, "true", 1] do
        json = Map.put(@json, "dividends", [Map.put(dividend, "forecast", mark)])
        assert {:ok, %{dividends: []}} = Response.symbol(json)
      end

      for mark <- [false, nil] do
        json = Map.put(@json, "dividends", [Map.put(dividend, "forecast", mark)])
        assert {:ok, %{dividends: [_dividend]}} = Response.symbol(json)
      end
    end

    test "dividends that are not a list make the answer invalid, so the stored data stays" do
      assert Response.symbol(Map.put(@json, "dividends", "none")) == {:error, :invalid_response}
    end
  end

  describe "available?/0" do
    setup do
      config = Application.get_env(:abakus, DivvyDiary)
      on_exit(fn -> Application.put_env(:abakus, DivvyDiary, config || []) end)
    end

    test "only with an API key" do
      Application.put_env(:abakus, DivvyDiary, api_key: nil)
      refute DivvyDiary.available?()

      Application.put_env(:abakus, DivvyDiary, api_key: "")
      refute DivvyDiary.available?()

      Application.put_env(:abakus, DivvyDiary, api_key: "key")
      assert DivvyDiary.available?()
    end
  end
end
