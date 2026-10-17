defmodule Abakus.Depot.PriceChartTest do
  use ExUnit.Case, async: true

  import Abakus.Depot.PortfoliosFixtures, only: [money: 1, shares: 1]
  import Abakus.Depot.SecuritiesFixtures, only: [price: 1]

  alias Abakus.Depot.Portfolios.{Transaction, TransactionUnit}
  alias Abakus.Depot.PriceChart
  alias Abakus.Depot.Securities.Security

  @today ~D[2026-10-09]
  @year Date.range(~D[2025-10-09], @today)

  defp security(attrs \\ []), do: struct!(%Security{id: 20, currency: "EUR"}, attrs)

  defp trade(type, date, count, amount, attrs \\ []) do
    struct!(
      %Transaction{
        type: type,
        date_time: NaiveDateTime.new!(date, ~T[12:00:00]),
        portfolio_id: 1,
        security_id: 20,
        shares: shares(count),
        amount: money(amount),
        units: []
      },
      attrs
    )
  end

  defp prices(chart), do: Enum.map(chart.prices, &{&1.date, &1.price})

  describe "prices" do
    test "are the closes of a period of up to a year" do
      closes = [
        {~D[2025-10-08], price(90)},
        {~D[2025-10-10], price(91)},
        {~D[2026-10-08], price(99)}
      ]

      chart = PriceChart.of(security(), closes, [], @year)

      assert prices(chart) == [{~D[2025-10-10], price(91)}, {~D[2026-10-08], price(99)}]
    end

    test "end with the latest quote unless a close is newer, as PP's prices do" do
      closes = [{~D[2026-10-07], price(98)}, {~D[2026-10-08], price(99)}]
      quoted = security(latest_date: @today, latest_close: price(101))
      same_day = security(latest_date: ~D[2026-10-08], latest_close: price(100))
      older = security(latest_date: ~D[2026-10-07], latest_close: price(97))

      assert prices(PriceChart.of(quoted, closes, [], @year)) ==
               [{~D[2026-10-07], price(98)}, {~D[2026-10-08], price(99)}, {@today, price(101)}]

      assert prices(PriceChart.of(same_day, closes, [], @year)) ==
               [{~D[2026-10-07], price(98)}, {~D[2026-10-08], price(100)}]

      assert prices(PriceChart.of(older, closes, [], @year)) ==
               [{~D[2026-10-07], price(98)}, {~D[2026-10-08], price(99)}]
    end

    test "are the latest quote alone without any close" do
      quoted = security(latest_date: @today, latest_close: price(101))

      assert prices(PriceChart.of(quoted, [], [], @year)) == [{@today, price(101)}]
    end

    test "keep the last close on or before every seventh day beyond a year and every trade's day" do
      range = Date.range(~D[2021-10-09], @today)
      closes = for day <- range, Date.day_of_week(day) <= 5, do: {day, price(100)}
      # A Tuesday and a Saturday, between two kept days.
      trades = [trade(:buy, ~D[2024-03-05], 1, 100), trade(:sell, ~D[2024-03-09], 1, 100)]

      days = PriceChart.of(security(), closes, trades, range).prices |> Enum.map(& &1.date)

      # Every seventh day counting back from Friday, 9 October, is a Friday.
      assert ~D[2024-03-05] in days
      assert ~D[2024-03-08] in days
      refute ~D[2024-03-07] in days
      assert List.last(days) == @today
      assert length(days) in 260..264
      assert days == Enum.sort(Enum.uniq(days), Date)
    end
  end

  describe "trades" do
    test "are the purchases and sales with their price per share before fees, in order" do
      fee = %TransactionUnit{type: :fee, amount: money(10)}

      transactions = [
        trade(:sell, ~D[2026-06-01], 4, 480),
        trade(:buy, ~D[2026-02-02], 10, 1_010, units: [fee]),
        trade(:inbound_delivery, ~D[2026-03-02], 5, 550),
        trade(:outbound_delivery, ~D[2026-07-01], 1, 130),
        trade(:security_transfer, ~D[2026-08-03], 1, 0, other_portfolio_id: 2),
        trade(:dividend, ~D[2026-09-01], 0, 20)
      ]

      chart = PriceChart.of(security(), [{~D[2026-01-02], price(100)}], transactions, @year)

      assert chart.trades == [
               %{date: ~D[2026-02-02], type: :buy, shares: shares(10), price: price(100)},
               %{
                 date: ~D[2026-03-02],
                 type: :inbound_delivery,
                 shares: shares(5),
                 price: price(110)
               },
               %{date: ~D[2026-06-01], type: :sell, shares: shares(4), price: price(120)},
               %{
                 date: ~D[2026-07-01],
                 type: :outbound_delivery,
                 shares: shares(1),
                 price: price(130)
               }
             ]
    end

    test "leave out the trades before the period" do
      transactions = [trade(:buy, ~D[2025-10-08], 1, 90), trade(:buy, ~D[2025-10-09], 1, 91)]

      chart = PriceChart.of(security(), [{~D[2025-10-01], price(90)}], transactions, @year)

      assert Enum.map(chart.trades, & &1.date) == [~D[2025-10-09]]
    end

    test "put a trade of a security not in euros at the price of its day" do
      usd = security(currency: "USD")
      closes = [{~D[2026-03-02], price(110)}, {~D[2026-03-04], price(112)}]

      chart = PriceChart.of(usd, closes, [trade(:buy, ~D[2026-03-03], 10, 1_000)], @year)

      assert [%{date: ~D[2026-03-03], price: 11_000_000_000}] = chart.trades
    end

    test "leave out a trade without any price known" do
      usd = security(currency: "USD")

      assert PriceChart.of(usd, [], [trade(:buy, ~D[2026-03-03], 10, 1_000)], @year).trades == []
    end
  end
end
