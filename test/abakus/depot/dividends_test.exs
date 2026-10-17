defmodule Abakus.Depot.DividendsTest do
  use ExUnit.Case, async: true

  import Abakus.Depot.PortfoliosFixtures, only: [money: 1, shares: 1]

  alias Abakus.Depot.Dividends
  alias Abakus.Depot.Portfolios.{Transaction, TransactionUnit}
  alias Abakus.Depot.Securities.{DivvyDiaryDividend, Security}
  alias Abakus.Depot.Valuation.Market

  @fund %Security{id: 1, name: "All-World", currency: "EUR"}
  @dollar_fund %Security{id: 2, name: "Quality", currency: "USD"}
  @market Market.new([@fund, @dollar_fund], [], [])
  @today ~D[2026-10-10]

  defp dividend(date, net, attrs \\ []) do
    struct!(
      %Transaction{
        type: :dividend,
        date_time: NaiveDateTime.new!(date, ~T[09:00:00]),
        account_id: 10,
        security_id: @fund.id,
        shares: shares(10),
        amount: money(net),
        units: []
      },
      attrs
    )
  end

  defp unit(type, amount), do: %TransactionUnit{type: type, amount: money(amount)}

  describe "received/2" do
    test "gives each dividend with gross, taxes, fees and net, newest first" do
      older = dividend(~D[2026-03-31], 10)
      newer = dividend(~D[2026-09-30], 15, units: [unit(:tax, 4.5), unit(:fee, 0.5)])

      assert Dividends.received([older, newer], @market) == [
               %{
                 date: ~D[2026-09-30],
                 security: @fund,
                 shares: shares(10),
                 gross: money(20),
                 taxes: money(4.5),
                 fees: money(0.5),
                 net: money(15)
               },
               %{
                 date: ~D[2026-03-31],
                 security: @fund,
                 shares: shares(10),
                 gross: money(10),
                 taxes: 0,
                 fees: 0,
                 net: money(10)
               }
             ]
    end

    test "counts only dividends, not interest" do
      interest = %{dividend(~D[2026-09-30], 7) | type: :interest, security_id: nil}

      assert Dividends.received([interest, dividend(~D[2026-09-30], 5)], @market)
             |> Enum.map(& &1.net) == [money(5)]
    end

    test "takes the euros booked for a security in another currency, whatever the rate" do
      market =
        Market.new([@fund, @dollar_fund], [], [{"USD", ~D[2026-09-30], Decimal.new("1.25")}])

      dividend =
        dividend(~D[2026-09-30], 16, security_id: @dollar_fund.id, units: [unit(:tax, 4)])

      assert [%{gross: gross, taxes: taxes, net: net}] = Dividends.received([dividend], market)
      assert {gross, taxes, net} == {money(20), money(4), money(16)}
    end

    test "takes a dividend without shares as zero shares" do
      assert [%{shares: 0}] =
               Dividends.received([dividend(~D[2026-09-30], 5, shares: nil)], @market)
    end
  end

  describe "by_year/2" do
    test "adds up gross and net per month and year, newest year first" do
      received =
        Dividends.received(
          [
            dividend(~D[2025-03-31], 8, units: [unit(:tax, 2)]),
            dividend(~D[2026-03-02], 9, units: [unit(:tax, 1)]),
            dividend(~D[2026-03-31], 5),
            dividend(~D[2026-09-30], 4)
          ],
          @market
        )

      assert [this_year, last_year] = Dividends.by_year(received, ~D[2026-10-10])

      assert this_year.year == 2026
      assert Enum.at(this_year.months, 2) == %{gross: money(15), net: money(14)}
      assert Enum.at(this_year.months, 8) == %{gross: money(4), net: money(4)}
      assert Enum.at(this_year.months, 0) == %{gross: 0, net: 0}
      assert length(this_year.months) == 12
      assert {this_year.gross, this_year.net} == {money(19), money(18)}

      assert last_year.year == 2025
      assert {last_year.gross, last_year.net} == {money(10), money(8)}
    end

    test "lists every year from the first dividend to this year, those without any at zero" do
      received = Dividends.received([dividend(~D[2023-06-30], 5)], @market)

      assert Dividends.by_year(received, ~D[2026-10-10])
             |> Enum.map(&{&1.year, &1.net}) == [
               {2026, 0},
               {2025, 0},
               {2024, 0},
               {2023, money(5)}
             ]
    end

    test "is empty without dividends" do
      assert Dividends.by_year([], ~D[2026-10-10]) == []
    end
  end

  describe "total/2" do
    test "adds up gross and net of the dividends paid in the range" do
      received =
        Dividends.received(
          [
            dividend(~D[2025-12-31], 3),
            dividend(~D[2026-01-01], 8, units: [unit(:tax, 2)]),
            dividend(~D[2026-10-10], 5),
            dividend(~D[2026-10-11], 7)
          ],
          @market
        )

      assert Dividends.total(received, Date.range(~D[2026-01-01], ~D[2026-10-10])) ==
               %{gross: money(15), net: money(13)}
    end
  end

  describe "upcoming/4" do
    defp buy(date, count, security \\ @fund) do
      %Transaction{
        type: :buy,
        date_time: NaiveDateTime.new!(date, ~T[10:00:00]),
        portfolio_id: 20,
        security_id: security.id,
        shares: shares(count),
        amount: 0,
        units: []
      }
    end

    defp sell(date, count), do: %{buy(date, count) | type: :sell}

    defp stored(ex_date, pay_date, per_share, attrs \\ []) do
      struct!(
        %DivvyDiaryDividend{
          security_id: @fund.id,
          ex_date: ex_date,
          pay_date: pay_date,
          per_share: round(per_share * 100_000_000),
          currency: "EUR"
        },
        attrs
      )
    end

    defp upcoming(transactions, stored, market \\ @market),
      do: Dividends.upcoming(transactions, stored, market, @today)

    test "an announced dividend counts the shares held at the end of its ex date" do
      transactions = [buy(~D[2026-01-05], 100), buy(~D[2026-10-05], 50)]

      assert [dividend] =
               upcoming(transactions, [stored(~D[2026-10-01], ~D[2026-10-20], 0.5)])

      assert %{
               kind: :announced,
               security: @fund,
               ex_date: ~D[2026-10-01],
               pay_date: ~D[2026-10-20],
               per_share: 50_000_000,
               currency: "EUR"
             } = dividend

      assert {dividend.shares, dividend.gross} == {shares(100), money(50)}
    end

    test "an announced dividend with its ex date still to come counts today's shares" do
      transactions = [buy(~D[2026-01-05], 100), buy(~D[2026-10-10], 50)]

      assert [%{shares: shares, gross: gross}] =
               upcoming(transactions, [stored(~D[2026-10-15], ~D[2026-10-20], 0.5)])

      assert {shares, gross} == {shares(150), money(75)}
    end

    test "an announced dividend for shares sold before its ex date is left out" do
      transactions = [buy(~D[2026-01-05], 100), sell(~D[2026-09-30], 100)]

      assert upcoming(transactions, [stored(~D[2026-10-01], ~D[2026-10-20], 0.5)]) == []
    end

    test "forecasts the dividends of the last 12 months one year later with today's shares" do
      dividends = [
        stored(~D[2025-12-01], ~D[2025-12-15], 0.4),
        stored(~D[2026-03-01], ~D[2026-03-15], 0.4)
      ]

      assert [december, march] = upcoming([buy(~D[2024-01-05], 200)], dividends)

      assert %{kind: :forecast, ex_date: ~D[2026-12-01], pay_date: ~D[2026-12-15]} = december
      assert {december.shares, december.gross} == {shares(200), money(80)}
      assert %{kind: :forecast, pay_date: ~D[2027-03-15], gross: gross} = march
      assert gross == money(80)
    end

    test "forecasts only for securities held today" do
      transactions = [buy(~D[2025-01-05], 200), sell(~D[2026-06-01], 200)]

      assert upcoming(transactions, [stored(~D[2025-12-01], ~D[2025-12-15], 0.4)]) == []
    end

    test "an announced dividend replaces the forecast up to its pay date" do
      dividends = [
        stored(~D[2025-03-01], ~D[2025-03-15], 0.4),
        stored(~D[2025-12-01], ~D[2025-12-15], 0.4),
        stored(~D[2026-03-01], ~D[2026-03-15], 0.4),
        stored(~D[2026-12-04], ~D[2026-12-18], 0.45)
      ]

      assert [december, march] = upcoming([buy(~D[2024-01-05], 200)], dividends)
      assert {december.kind, december.pay_date} == {:announced, ~D[2026-12-18]}
      assert {march.kind, march.pay_date} == {:forecast, ~D[2027-03-15]}
    end

    test "an announced dividend replaces the forecast of its month even when paid earlier" do
      dividends = [
        stored(~D[2025-12-01], ~D[2025-12-15], 0.4),
        stored(~D[2026-11-28], ~D[2026-12-12], 0.45)
      ]

      assert [%{kind: :announced, pay_date: ~D[2026-12-12]}] =
               upcoming([buy(~D[2024-01-05], 200)], dividends)
    end

    test "a dividend paid this month replaces the forecast of this month" do
      dividends = [
        stored(~D[2025-10-01], ~D[2025-10-15], 0.5),
        stored(~D[2026-09-28], ~D[2026-10-05], 0.5)
      ]

      transactions = [buy(~D[2025-01-02], 100), dividend(~D[2026-10-05], 50, shares: shares(100))]

      assert upcoming(transactions, dividends) == []
    end

    test "without DivvyDiary dividends a distribution this month replaces its forecast" do
      transactions = [
        buy(~D[2025-01-02], 10),
        dividend(~D[2025-10-15], 10),
        dividend(~D[2026-10-05], 10)
      ]

      assert upcoming(transactions, []) == []
    end

    test "covers the rest of this month and the next eleven" do
      dividends = [
        stored(~D[2025-10-01], ~D[2025-10-05], 0.1),
        stored(~D[2025-10-10], ~D[2025-10-11], 0.1),
        stored(~D[2026-09-20], ~D[2026-09-30], 0.1)
      ]

      assert upcoming([buy(~D[2024-01-05], 10)], dividends) |> Enum.map(& &1.pay_date) ==
               [~D[2026-10-11], ~D[2027-09-30]]

      assert upcoming([buy(~D[2024-01-05], 10)], [stored(nil, ~D[2027-10-01], 0.1)]) == []
    end

    test "with a year of dividends forecasts each one year later, not the latest" do
      dividends = [
        stored(~D[2025-09-01], ~D[2025-09-15], 0.3),
        stored(~D[2025-12-01], ~D[2025-12-15], 0.3),
        stored(~D[2026-03-01], ~D[2026-03-15], 0.4),
        stored(~D[2026-06-01], ~D[2026-06-15], 0.5),
        stored(~D[2026-09-01], ~D[2026-09-15], 0.6)
      ]

      assert upcoming([buy(~D[2024-01-05], 10)], dividends)
             |> Enum.map(&{&1.pay_date, &1.per_share}) == [
               {~D[2026-12-15], 30_000_000},
               {~D[2027-03-15], 40_000_000},
               {~D[2027-06-15], 50_000_000},
               {~D[2027-09-15], 60_000_000}
             ]
    end

    test "with less than a year of monthly dividends repeats the latest every month" do
      dividends = [
        stored(nil, ~D[2026-06-15], 0.03),
        stored(nil, ~D[2026-07-15], 0.03),
        stored(nil, ~D[2026-08-15], 0.03),
        stored(nil, ~D[2026-09-15], 0.03),
        stored(nil, ~D[2026-10-05], 0.04)
      ]

      forecasts = upcoming([buy(~D[2026-05-05], 10)], dividends)

      assert Enum.map(forecasts, & &1.pay_date) ==
               Enum.map(1..11, &Date.shift(~D[2026-10-05], month: &1))

      assert Enum.all?(forecasts, &match?(%{kind: :forecast, per_share: 4_000_000}, &1))
    end

    test "with less than a year of quarterly dividends repeats the latest every third month" do
      dividends = [
        stored(~D[2026-03-10], ~D[2026-03-20], 0.5),
        stored(~D[2026-06-10], ~D[2026-06-20], 0.5),
        stored(~D[2026-09-10], ~D[2026-09-20], 0.6)
      ]

      forecasts = upcoming([buy(~D[2026-01-05], 10)], dividends)

      assert Enum.map(forecasts, &{&1.ex_date, &1.pay_date, &1.per_share}) == [
               {~D[2026-12-10], ~D[2026-12-20], 60_000_000},
               {~D[2027-03-10], ~D[2027-03-20], 60_000_000},
               {~D[2027-06-10], ~D[2027-06-20], 60_000_000},
               {~D[2027-09-10], ~D[2027-09-20], 60_000_000}
             ]
    end

    test "with less than a year of dividends repeats each one of the latest pay date" do
      dividends = [
        stored(nil, ~D[2026-07-15], 0.03),
        stored(nil, ~D[2026-08-15], 0.03),
        stored(nil, ~D[2026-09-15], 0.5),
        stored(nil, ~D[2026-09-15], 0.03)
      ]

      forecasts = upcoming([buy(~D[2026-07-01], 10)], dividends)

      assert forecasts |> Enum.take(2) |> Enum.map(&{&1.pay_date, &1.per_share}) |> Enum.sort() ==
               [{~D[2026-10-15], 3_000_000}, {~D[2026-10-15], 50_000_000}]

      assert length(forecasts) == 24
    end

    test "with dividends on only two pay dates within a year forecasts each one year later" do
      transactions = [
        buy(~D[2026-01-05], 10),
        dividend(~D[2026-05-20], 10),
        dividend(~D[2026-09-20], 10)
      ]

      assert upcoming(transactions, []) |> Enum.map(& &1.pay_date) ==
               [~D[2027-05-20], ~D[2027-09-20]]
    end

    test "with less than a year of dividends repeats an announced one after it" do
      dividends = [
        stored(nil, ~D[2026-08-15], 0.03),
        stored(nil, ~D[2026-09-15], 0.03),
        stored(nil, ~D[2026-11-05], 0.05)
      ]

      assert [%{kind: :announced, pay_date: ~D[2026-11-05]} | forecasts] =
               upcoming([buy(~D[2026-07-01], 10)], dividends)

      assert Enum.map(forecasts, &{&1.pay_date, &1.per_share}) ==
               Enum.map(1..10, &{Date.shift(~D[2026-11-05], month: &1), 5_000_000})
    end

    test "with less than a year of own distributions repeats the latest in its rhythm" do
      transactions = [
        buy(~D[2026-06-01], 10),
        dividend(~D[2026-07-01], 10),
        dividend(~D[2026-08-01], 10),
        dividend(~D[2026-09-01], 10),
        dividend(~D[2026-10-01], 12)
      ]

      forecasts = upcoming(transactions, [])

      assert Enum.map(forecasts, &{&1.pay_date, &1.per_share}) ==
               Enum.map(1..11, &{Date.shift(~D[2026-10-01], month: &1), 120_000_000})
    end

    test "without DivvyDiary dividends the user's own distributions stand in" do
      transactions = [
        buy(~D[2026-01-05], 10),
        dividend(~D[2026-06-01], 10, ex_date: ~N[2026-05-20 00:00:00]),
        buy(~D[2026-07-01], 20)
      ]

      assert [forecast] = upcoming(transactions, [])

      assert %{kind: :forecast, ex_date: ~D[2027-05-20], pay_date: ~D[2027-06-01]} = forecast

      assert {forecast.per_share, forecast.shares, forecast.gross} ==
               {100_000_000, shares(30), money(30)}
    end

    test "the user's own distributions of a security in another currency stay in euros" do
      market =
        Market.new([@fund, @dollar_fund], [], [{"USD", ~D[2026-10-09], Decimal.new("1.25")}])

      transactions = [
        buy(~D[2026-01-05], 10, @dollar_fund),
        dividend(~D[2026-06-01], 10, security_id: @dollar_fund.id)
      ]

      assert [%{currency: "EUR", per_share: 100_000_000, gross: gross}] =
               upcoming(transactions, [], market)

      assert gross == money(10)
    end

    test "with DivvyDiary dividends, even only old ones, the user's own do not count" do
      transactions = [buy(~D[2026-01-05], 10), dividend(~D[2026-06-01], 10)]

      assert upcoming(transactions, [stored(~D[2023-05-20], ~D[2023-06-01], 1)]) == []
    end

    test "estimates net from the security's dividends of the last 12 months" do
      transactions = [
        buy(~D[2025-01-05], 100),
        dividend(~D[2025-10-10], 1000, units: [unit(:tax, 1000)]),
        dividend(~D[2025-11-01], 163, units: [unit(:tax, 37)])
      ]

      assert [%{gross: gross, net: net, net_is_gross: false}] =
               upcoming(transactions, [stored(~D[2026-10-30], ~D[2026-11-10], 1)])

      assert {gross, net} == {money(100), money(81.5)}
    end

    test "estimates net from the dividends received where they are at hand" do
      transactions = [
        buy(~D[2025-01-05], 100),
        dividend(~D[2025-11-01], 163, units: [unit(:tax, 37)])
      ]

      received = Dividends.received(transactions, @market)
      stored = [stored(~D[2026-10-30], ~D[2026-11-10], 1)]

      assert Dividends.upcoming(transactions, stored, @market, @today, received: received) ==
               upcoming(transactions, stored)

      assert [%{net: net}] =
               Dividends.upcoming(transactions, stored, @market, @today, received: [])

      assert net == money(100)
    end

    test "a dividend booked without a security counts for no security's net" do
      transactions = [
        buy(~D[2025-01-05], 100),
        dividend(~D[2026-09-01], 7, security_id: nil, shares: nil, units: [unit(:tax, 7)]),
        dividend(~D[2025-11-01], 163, units: [unit(:tax, 37)])
      ]

      assert [%{gross: gross, net: net, net_is_gross: false}] =
               upcoming(transactions, [stored(~D[2026-10-30], ~D[2026-11-10], 1)])

      assert {gross, net} == {money(100), money(81.5)}
    end

    test "stays gross without dividends booked in the last 12 months, and says so" do
      transactions = [buy(~D[2025-01-05], 100), dividend(~D[2025-10-10], 50)]

      assert [%{gross: gross, net: net, net_is_gross: true}] =
               upcoming(transactions, [stored(~D[2026-10-30], ~D[2026-11-10], 1)])

      assert gross == net
    end

    test "converts at the latest ECB rate" do
      market =
        Market.new([@fund, @dollar_fund], [], [
          {"USD", ~D[2026-10-08], Decimal.new("1.25")},
          {"USD", ~D[2026-10-09], Decimal.new("1.10")}
        ])

      dividend = stored(nil, ~D[2026-12-20], 1.1, security_id: @dollar_fund.id, currency: "USD")

      assert [%{gross: gross, ex_date: nil, currency: "USD"}] =
               upcoming([buy(~D[2026-01-05], 100, @dollar_fund)], [dividend], market)

      assert gross == money(100)
    end

    test "comes by pay date" do
      dividends = [
        stored(~D[2026-11-01], ~D[2026-11-20], 1),
        stored(~D[2026-10-12], ~D[2026-10-15], 1, security_id: @dollar_fund.id)
      ]

      transactions = [buy(~D[2026-01-05], 1), buy(~D[2026-01-05], 1, @dollar_fund)]

      assert upcoming(transactions, dividends) |> Enum.map(& &1.pay_date) ==
               [~D[2026-10-15], ~D[2026-11-20]]
    end
  end

  describe "by_coming_month/2" do
    test "adds up announced and forecast dividends for this month and the next eleven" do
      upcoming = [
        %{kind: :announced, pay_date: ~D[2026-10-20], gross: 100, net: 80},
        %{kind: :forecast, pay_date: ~D[2026-10-30], gross: 50, net: 40},
        %{kind: :forecast, pay_date: ~D[2027-09-30], gross: 10, net: 10}
      ]

      assert [october | _] = months = Dividends.by_coming_month(upcoming, @today)
      assert length(months) == 12

      assert october == %{
               month: ~D[2026-10-01],
               announced: %{gross: 100, net: 80},
               forecast: %{gross: 50, net: 40}
             }

      assert %{month: ~D[2027-09-01], forecast: %{gross: 10}, announced: %{gross: 0}} =
               List.last(months)
    end
  end
end
