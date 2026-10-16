defmodule Abakus.Depot.Valuation.MarketTest do
  use ExUnit.Case, async: true

  import Abakus.Depot.PortfoliosFixtures, only: [money: 1]

  alias Abakus.Depot.Securities.Security
  alias Abakus.Depot.Valuation.Market

  @wednesday ~D[2026-09-30]
  @thursday ~D[2026-10-01]
  @friday ~D[2026-10-02]
  @saturday ~D[2026-10-03]

  defp market(closes, quote \\ nil) do
    {quote_date, quote_close} = quote || {nil, nil}

    security = %Security{
      id: 1,
      currency: "EUR",
      latest_date: quote_date,
      latest_close: quote_close
    }

    Market.new([security], Enum.map(closes, fn {date, close} -> {1, date, close} end), [])
  end

  defp weekend?(date), do: Date.day_of_week(date) > 5

  defp rates(usd_rates) do
    rates = Enum.map(usd_rates, fn {date, rate} -> {"USD", date, Decimal.new(rate)} end)
    Market.new([], [], rates)
  end

  describe "price/3" do
    test "is the close of the day" do
      assert Market.price(market([{@thursday, 99}, {@friday, 100}]), 1, @thursday) == 99
    end

    test "is the last close before a day without one" do
      assert Market.price(market([{@thursday, 99}, {@friday, 100}]), 1, @saturday) == 100
    end

    test "is the first close on a day before it, as in PP" do
      assert Market.price(market([{@thursday, 99}, {@friday, 100}]), 1, @wednesday) == 99
    end

    test "is the last close before any day of a long history" do
      weekdays = Enum.reject(Date.range(~D[2025-01-01], ~D[2026-12-31]), &weekend?/1)
      market = market(Enum.map(weekdays, &{&1, Date.to_gregorian_days(&1)}))

      for date <- Date.range(~D[2025-01-01], ~D[2026-12-31]) do
        friday = Date.add(date, -max(Date.day_of_week(date) - 5, 0))
        assert Market.price(market, 1, date) == Date.to_gregorian_days(friday)
      end
    end

    test "is nil for a security without any price" do
      assert Market.price(market([]), 1, @friday) == nil
      assert Market.price(market([]), 2, @friday) == nil
    end

    test "is the latest quote from its day on" do
      market = market([{@friday, 100}], {@saturday, 102})

      assert Market.price(market, 1, @friday) == 100
      assert Market.price(market, 1, @saturday) == 102
      assert Market.price(market, 1, Date.add(@saturday, 2)) == 102
    end

    test "is the latest quote on the day of the last close" do
      assert Market.price(market([{@friday, 100}], {@friday, 101}), 1, @friday) == 101
    end

    test "leaves out a quote older than the last close, as PP does" do
      market = market([{@wednesday, 98}, {@friday, 100}], {@thursday, 99})

      assert Market.price(market, 1, @thursday) == 98
      assert Market.price(market, 1, @saturday) == 100
    end

    test "is the latest quote on any day for a security without closes, as in PP" do
      assert Market.price(market([], {@friday, 102}), 1, @wednesday) == 102
    end
  end

  describe "price_days/2" do
    test "are the first and the last close" do
      assert Market.price_days(market([{@wednesday, 98}, {@friday, 100}]), 1) ==
               {@wednesday, @friday}
    end

    test "count the latest quote as a price, as PP does" do
      assert Market.price_days(market([{@thursday, 99}], {@saturday, 102}), 1) ==
               {@thursday, @saturday}

      assert Market.price_days(market([], {@friday, 102}), 1) == {@friday, @friday}
    end

    test "are nil without any price" do
      assert Market.price_days(market([]), 1) == nil
      assert Market.price_days(market([]), 2) == nil
    end
  end

  test "security/2 and currency/2 are the security and its currency" do
    security = %Security{id: 1, currency: "USD"}
    market = Market.new([security], [], [])

    assert Market.security(market, 1) == security
    assert Market.currency(market, 1) == "USD"
  end

  describe "to_euros/4" do
    test "leaves euros as they are" do
      assert Market.to_euros(rates([]), money(123.45), "EUR", @friday) == money(123.45)
    end

    test "divides by the ECB rate of the day" do
      assert Market.to_euros(rates([{@friday, "1.10"}]), money(1_100), "USD", @friday) ==
               money(1_000)
    end

    test "takes the last rate before a day without one" do
      market = rates([{@thursday, "1.25"}, {@friday, "1.10"}])

      assert Market.to_euros(market, money(1_100), "USD", @saturday) == money(1_000)
    end

    test "takes the first rate on a day before it, as PP does" do
      assert Market.to_euros(rates([{@friday, "1.10"}]), money(1_100), "USD", @thursday) ==
               money(1_000)
    end

    test "multiplies by the inverse rate to ten places, as PP does" do
      market = rates([{@friday, "3"}])

      assert Market.to_euros(market, 100_000_000_000, "USD", @friday) == 33_333_333_330
    end

    test "rounds half down, as PP does" do
      assert Market.to_euros(rates([{@friday, "2"}]), 101, "USD", @friday) == 50
    end

    test "leaves an amount without any rate as it is, as PP does" do
      assert Market.to_euros(rates([]), money(1_100), "USD", @friday) == money(1_100)
    end

    test "converts pence, agorot and cents at a hundredth of the main currency's rate, as PP does" do
      for {currency, main} <- [{"GBX", "GBP"}, {"ILA", "ILS"}, {"ZAC", "ZAR"}] do
        market = Market.new([], [], [{main, @friday, Decimal.new("0.85")}])

        assert Market.to_euros(market, money(500_000), currency, @friday) == money(5_882.35)
      end
    end
  end

  test "rate_currencies/1 adds the main currency of pence, agorot and cents" do
    assert Market.rate_currencies(["EUR", "GBX", "USD", "GBP"]) == ["EUR", "GBX", "GBP", "USD"]
  end
end
