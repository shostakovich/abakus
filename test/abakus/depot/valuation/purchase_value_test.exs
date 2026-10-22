defmodule Abakus.Depot.Valuation.PurchaseValueTest do
  use ExUnit.Case, async: true

  import Abakus.Depot.PortfoliosFixtures, only: [money: 1, shares: 1]

  alias Abakus.Depot.Portfolios.{Transaction, TransactionUnit}
  alias Abakus.Depot.Valuation.PurchaseValue

  @day ~D[2026-10-01]

  # Portfolios 1 and 2, securities 20 and 21.
  defp transaction(type, days, portfolio_id, count, amount, attrs \\ []) do
    struct!(
      %Transaction{
        type: type,
        date_time: NaiveDateTime.new!(Date.add(@day, days), ~T[12:00:00]),
        portfolio_id: portfolio_id,
        security_id: 20,
        shares: shares(count),
        amount: money(amount),
        units: []
      },
      attrs
    )
  end

  defp purchase_values(transactions, date \\ Date.add(@day, 100)),
    do: PurchaseValue.by_holding(transactions, date)

  test "the remaining shares after a partial sale cost what their purchases cost, by FIFO" do
    fee = %TransactionUnit{type: :fee, amount: money(10)}

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

    # Portfolio 2 sells the 10 oldest, the first purchase's, and keeps 5 of the second (600 €) and its own 10 (1,500 €).
    assert purchase_values(transactions) == %{
             {1, 20} => money(600),
             {2, 20} => money(600) + money(1_500)
           }
  end

  test "counts each security apart" do
    transactions = [
      transaction(:buy, 0, 1, 1, 100),
      transaction(:buy, 0, 1, 1, 200, security_id: 21)
    ]

    assert purchase_values(transactions) == %{{1, 20} => money(100), {1, 21} => money(200)}
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
