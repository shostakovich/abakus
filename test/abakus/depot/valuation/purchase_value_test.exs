defmodule Abakus.Depot.Valuation.PurchaseValueTest do
  use ExUnit.Case, async: true

  import Abakus.Depot.PortfoliosFixtures, only: [money: 1, shares: 1]

  alias Abakus.Depot.Portfolios.{Transaction, TransactionUnit}
  alias Abakus.Depot.Securities.Security
  alias Abakus.Depot.Valuation.{Market, PurchaseValue}

  @day ~D[2026-10-01]

  # Portfolios 1 and 2, securities 20 (EUR) and 21 (USD).
  defp market(rates \\ []) do
    Market.new(
      [%Security{id: 20, currency: "EUR"}, %Security{id: 21, currency: "USD"}],
      [],
      rates
    )
  end

  defp transaction(type, days, portfolio_id, count, amount, attrs \\ []) do
    struct!(
      %Transaction{
        type: type,
        date_time: NaiveDateTime.new!(Date.add(@day, days), ~T[12:00:00]),
        portfolio_id: portfolio_id,
        security_id: 20,
        shares: shares(count),
        amount: money(amount),
        currency: "EUR",
        units: []
      },
      attrs
    )
  end

  defp purchase_values(transactions, date \\ Date.add(@day, 100)),
    do: PurchaseValue.by_holding(transactions, market(), date)

  test "the remaining shares after a partial sale cost what their purchases cost, by FIFO" do
    fee = %TransactionUnit{type: :fee, amount: money(10), currency: "EUR"}

    transactions = [
      transaction(:buy, 0, 1, 10, 1_000),
      transaction(:buy, 1, 1, 10, 1_210, units: [fee]),
      transaction(:sell, 2, 1, 15, 1_800)
    ]

    assert purchase_values(transactions) == %{{1, 20} => money(605)}
  end

  test "a sale takes its part of a purchase's cost, rounded" do
    transactions = [transaction(:buy, 0, 1, 3, 100), transaction(:sell, 1, 1, 1, 50)]

    assert purchase_values(transactions) == %{{1, 20} => 6_667}
  end

  test "deliveries in are purchases and deliveries out are sales" do
    transactions = [
      transaction(:inbound_delivery, 0, 1, 10, 500),
      transaction(:buy, 1, 1, 10, 700),
      transaction(:outbound_delivery, 2, 1, 12, 0)
    ]

    assert purchase_values(transactions) == %{{1, 20} => money(560)}
  end

  test "a sale takes the oldest shares of its own portfolio only" do
    transactions = [
      transaction(:buy, 0, 2, 10, 900),
      transaction(:buy, 1, 1, 10, 1_000),
      transaction(:buy, 2, 1, 10, 1_200),
      transaction(:sell, 3, 1, 10, 1_300)
    ]

    assert purchase_values(transactions) == %{{1, 20} => money(1_200), {2, 20} => money(900)}
  end

  test "a transfer moves the oldest shares with their cost, and they stay the oldest" do
    transactions = [
      transaction(:buy, 0, 1, 10, 1_000),
      transaction(:buy, 1, 1, 10, 1_200),
      transaction(:buy, 2, 2, 10, 1_500),
      transaction(:security_transfer, 3, 1, 15, 0, other_portfolio_id: 2),
      transaction(:sell, 4, 2, 10, 0)
    ]

    # Portfolio 2 holds 5 of the second purchase (600 €) and its own 10 (1,500 €), sells the
    # 10 oldest: the 10 of the first purchase, already its own after the transfer.
    assert purchase_values(transactions) == %{
             {1, 20} => money(600),
             {2, 20} => money(600) + money(1_500)
           }
  end

  test "counts each security apart" do
    transactions = [
      transaction(:buy, 0, 1, 1, 100),
      transaction(:buy, 0, 1, 1, 200, security_id: 21, currency: "EUR")
    ]

    assert purchase_values(transactions) == %{{1, 20} => money(100), {1, 21} => money(200)}
  end

  test "converts a purchase in another currency at the ECB rate of its day" do
    rates = [{"USD", @day, Decimal.new("1.10")}, {"USD", Date.add(@day, 1), Decimal.new("1.25")}]

    transactions = [transaction(:buy, 0, 1, 1, 110, security_id: 21, currency: "USD")]

    assert PurchaseValue.by_holding(transactions, market(rates), Date.add(@day, 1)) ==
             %{{1, 21} => money(100)}
  end

  test "converts a purchase of a security in euros at the rate booked with it, as PP does" do
    gross = %TransactionUnit{
      type: :gross_value,
      amount: money(1_090),
      currency: "USD",
      fx_amount: money(990.91),
      fx_currency: "EUR",
      fx_rate: Decimal.new("1.10")
    }

    fee = %TransactionUnit{type: :fee, amount: money(10), currency: "USD"}
    buy = transaction(:buy, 0, 1, 10, 1_100, currency: "USD", units: [gross, fee])
    market = market([{"USD", @day, Decimal.new("1.12")}])

    assert PurchaseValue.by_holding([buy], market, @day) == %{{1, 20} => money(1_000)}
  end

  test "converts a purchase of a security in euros without a booked rate at the ECB rate" do
    buy = transaction(:buy, 0, 1, 10, 1_120, currency: "USD")
    market = market([{"USD", @day, Decimal.new("1.12")}])

    assert PurchaseValue.by_holding([buy], market, @day) == %{{1, 20} => money(1_000)}
  end

  test "leaves out transactions after the day, and sold shares cost nothing" do
    transactions = [
      transaction(:buy, 0, 1, 1, 100),
      transaction(:sell, 1, 1, 1, 120),
      transaction(:buy, 2, 2, 1, 100)
    ]

    assert purchase_values(transactions, Date.add(@day, 1)) == %{{1, 20} => 0}
  end

  test "ignores what is sold or moved beyond the shares held, as PP does" do
    transactions = [
      transaction(:buy, 0, 1, 1, 100),
      transaction(:sell, 1, 1, 2, 240),
      transaction(:security_transfer, 2, 1, 1, 0, other_portfolio_id: 2)
    ]

    assert purchase_values(transactions) == %{{1, 20} => 0}
  end

  test "ignores transactions that move no shares" do
    transactions = [
      transaction(:buy, 0, 1, 1, 100),
      transaction(:dividend, 1, nil, 0, 5, account_id: 10)
    ]

    assert purchase_values(transactions) == %{{1, 20} => money(100)}
  end
end
