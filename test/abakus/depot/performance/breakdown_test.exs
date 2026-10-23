defmodule Abakus.Depot.Performance.BreakdownTest do
  use ExUnit.Case, async: true

  import Abakus.Depot.PortfoliosFixtures, only: [money: 1, shares: 1]
  import Abakus.Depot.SecuritiesFixtures, only: [price: 1]

  alias Abakus.Depot.Performance
  alias Abakus.Depot.Performance.Breakdown
  alias Abakus.Depot.Portfolios.{Portfolio, Transaction, TransactionUnit}
  alias Abakus.Depot.Securities.Security
  alias Abakus.Depot.Valuation.{Filter, Market}

  # Portfolios 1 and 2 settle against account 10. Security 20 is in EUR, security 21 in USD.
  @securities [%Security{id: 20, currency: "EUR"}, %Security{id: 21, currency: "USD"}]
  @interval Date.range(~D[2026-10-01], ~D[2026-10-09])

  defp transaction(type, date, attrs) do
    struct!(
      %Transaction{
        type: type,
        date_time: NaiveDateTime.new!(date, ~T[12:00:00]),
        amount: 0,
        units: []
      },
      attrs
    )
  end

  defp unit(type, euros), do: %TransactionUnit{type: type, amount: money(euros)}

  defp buy(date, portfolio_id, count, euros, attrs \\ []) do
    transaction(
      :buy,
      date,
      [
        portfolio_id: portfolio_id,
        account_id: 10,
        security_id: 20,
        shares: shares(count),
        amount: money(euros)
      ] ++ attrs
    )
  end

  defp breakdown(transactions, market, filter \\ Filter.all()) do
    index = Performance.index(transactions, market, filter, @interval)
    Breakdown.of(transactions, market, filter, index)
  end

  # Values on the reference day and the last day, gains and money in or out add up as in PP.
  defp assert_adds_up(breakdown) do
    assert breakdown.initial_value + breakdown.capital_gains + breakdown.realized_capital_gains +
             breakdown.earnings - breakdown.fees - breakdown.taxes + breakdown.transfers ==
             breakdown.final_value
  end

  test "breaks the change in value down into gains, earnings, fees, taxes and money in or out" do
    transactions = [
      transaction(:deposit, ~D[2026-09-30], account_id: 10, amount: money(1_000)),
      buy(~D[2026-09-30], 1, 10, 1_000),
      transaction(:deposit, ~D[2026-10-02], account_id: 10, amount: money(600)),
      buy(~D[2026-10-02], 1, 5, 505, units: [unit(:fee, 5)]),
      transaction(:sell, ~D[2026-10-05],
        portfolio_id: 1,
        account_id: 10,
        security_id: 20,
        shares: shares(6),
        amount: money(648),
        units: [unit(:tax, 10), unit(:fee, 2)]
      ),
      transaction(:dividend, ~D[2026-10-06],
        account_id: 10,
        security_id: 20,
        amount: money(15),
        units: [unit(:tax, 5)]
      ),
      transaction(:fee, ~D[2026-10-07], account_id: 10, amount: money(3)),
      transaction(:interest, ~D[2026-10-08], account_id: 10, amount: money(1))
    ]

    market =
      Market.new(
        @securities,
        [{20, ~D[2026-09-30], price(100)}, {20, ~D[2026-10-09], price(120)}],
        []
      )

    breakdown = breakdown(transactions, market)

    assert breakdown == %Breakdown{
             initial_value: money(1_000),
             capital_gains: money(180),
             realized_capital_gains: money(60),
             earnings: money(21),
             fees: money(10),
             taxes: money(15),
             transfers: money(600),
             final_value: money(1_836)
           }

    assert_adds_up(breakdown)
  end

  test "moves the cost of transferred shares with them" do
    transactions = [
      transaction(:deposit, ~D[2026-09-30], account_id: 10, amount: money(1_000)),
      buy(~D[2026-09-30], 1, 10, 1_000),
      transaction(:security_transfer, ~D[2026-10-02],
        portfolio_id: 1,
        other_portfolio_id: 2,
        security_id: 20,
        shares: shares(4),
        amount: money(400)
      ),
      transaction(:sell, ~D[2026-10-05],
        portfolio_id: 2,
        account_id: 10,
        security_id: 20,
        shares: shares(4),
        amount: money(440)
      )
    ]

    market =
      Market.new(
        @securities,
        [{20, ~D[2026-09-30], price(100)}, {20, ~D[2026-10-09], price(120)}],
        []
      )

    breakdown = breakdown(transactions, market)

    assert breakdown.realized_capital_gains == money(40)
    assert breakdown.capital_gains == money(120)
    assert_adds_up(breakdown)

    # For portfolio 1 with its account, the shares leave in an outbound delivery.
    filter = Filter.new([%Portfolio{id: 1, reference_account_id: 10}], [10], transactions)
    breakdown = breakdown(transactions, market, filter)

    assert breakdown.realized_capital_gains == 0
    assert breakdown.transfers == money(440 - 400)
    assert_adds_up(breakdown)
  end

  test "orders the trades of each security on their own, as PP does" do
    # 22's untimed transfer sorts between the 09:00 sale and 10:00 move; sorting all trades put the move first.
    at = fn time -> NaiveDateTime.new!(~D[2026-10-03], time) end
    transfer = [portfolio_id: 1, other_portfolio_id: 2, shares: shares(10), amount: money(1_000)]

    transactions = [
      transaction(:deposit, ~D[2026-09-30], account_id: 10, amount: money(3_500)),
      buy(~D[2026-09-30], 1, 10, 1_000),
      buy(~D[2026-09-30], 1, 10, 1_000, security_id: 22),
      buy(~D[2026-10-02], 2, 10, 1_500),
      transaction(
        :security_transfer,
        ~D[2026-10-03],
        [date_time: at.(~T[10:00:00]), security_id: 20] ++ transfer
      ),
      transaction(
        :security_transfer,
        ~D[2026-10-03],
        [date_time: at.(~T[00:00:00]), security_id: 22] ++ transfer
      ),
      transaction(:sell, ~D[2026-10-03],
        date_time: at.(~T[09:00:00]),
        portfolio_id: 2,
        account_id: 10,
        security_id: 20,
        shares: shares(10),
        amount: money(1_600)
      )
    ]

    market =
      Market.new(
        @securities ++ [%Security{id: 22, currency: "EUR"}],
        [{20, ~D[2026-09-30], price(100)}, {22, ~D[2026-09-30], price(100)}],
        []
      )

    breakdown = breakdown(transactions, market)

    assert breakdown.realized_capital_gains == money(100)
    assert_adds_up(breakdown)
  end

  test "takes a purchase of a foreign security at the euros booked for it" do
    # 10 shares for 1,000 €, at 110 USD and 1.25 USD per euro at the end.
    transactions = [
      transaction(:deposit, ~D[2026-09-30], account_id: 10, amount: money(1_000)),
      buy(~D[2026-10-02], 1, 10, 1_000, security_id: 21)
    ]

    market =
      Market.new(@securities, [{21, ~D[2026-10-09], price(110)}], [
        {"USD", ~D[2026-10-02], Decimal.new("1.10")},
        {"USD", ~D[2026-10-09], Decimal.new("1.25")}
      ])

    breakdown = breakdown(transactions, market)

    assert breakdown.capital_gains == money(880 - 1_000)
    assert_adds_up(breakdown)
  end

  test "values a foreign holding at the rate of the first and the last day" do
    # 10 shares at 100 USD and 1.10 USD per euro, at 110 USD and 1.25 at the end.
    transactions = [
      transaction(:inbound_delivery, ~D[2026-09-30],
        portfolio_id: 1,
        security_id: 21,
        shares: shares(10),
        amount: money(900)
      )
    ]

    market =
      Market.new(
        @securities,
        [{21, ~D[2026-09-30], price(100)}, {21, ~D[2026-10-09], price(110)}],
        [
          {"USD", ~D[2026-10-01], Decimal.new("1.10")},
          {"USD", ~D[2026-10-09], Decimal.new("1.25")}
        ]
      )

    breakdown = breakdown(transactions, market)

    assert breakdown.initial_value == 90_909
    assert breakdown.capital_gains == money(880) - 90_909
    assert_adds_up(breakdown)
  end
end
