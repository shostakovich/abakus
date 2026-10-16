defmodule Abakus.Depot.ValuationTest do
  use ExUnit.Case, async: true

  import Abakus.Depot.PortfoliosFixtures, only: [money: 1, shares: 1]
  import Abakus.Depot.SecuritiesFixtures, only: [price: 1]

  alias Abakus.Depot.Portfolios.{Account, Portfolio, Transaction, TransactionUnit}
  alias Abakus.Depot.Securities.Security
  alias Abakus.Depot.Valuation
  alias Abakus.Depot.Valuation.{Filter, Holding, Market}

  @thursday ~D[2026-10-01]
  @friday ~D[2026-10-02]
  @saturday ~D[2026-10-03]

  # Portfolios 1 and 2, accounts 10 (EUR) and 11 (USD), securities 20 (EUR) and 21 (USD).
  defp transaction(type, date, attrs) do
    struct!(
      %Transaction{
        type: type,
        date_time: NaiveDateTime.new!(date, ~T[12:00:00]),
        amount: 0,
        currency: "EUR",
        units: []
      },
      attrs
    )
  end

  defp in_portfolio(type, date, portfolio_id, security_id, count, attrs \\ []) do
    transaction(
      type,
      date,
      [portfolio_id: portfolio_id, security_id: security_id, shares: shares(count)] ++ attrs
    )
  end

  defp market(closes, opts \\ []) do
    securities = [
      %Security{
        id: 20,
        currency: "EUR",
        latest_date: opts[:quote_date],
        latest_close: opts[:quote]
      },
      %Security{id: 21, currency: "USD"}
    ]

    Market.new(securities, closes, opts[:rates] || [])
  end

  defp holding(security_id, count, last \\ nil),
    do: %Holding{portfolio_id: 1, security_id: security_id, shares: shares(count), last: last}

  defp shares_per_holding(holdings),
    do: holdings |> Enum.map(&{&1.portfolio_id, &1.security_id, &1.shares}) |> Enum.sort()

  describe "holdings/2" do
    test "a purchase adds shares and a sale removes them" do
      buy = in_portfolio(:buy, @thursday, 1, 20, 10, account_id: 10)
      sell = in_portfolio(:sell, @friday, 1, 20, 4, account_id: 10)

      assert Valuation.holdings([buy, sell], @friday) == [
               %Holding{
                 portfolio_id: 1,
                 security_id: 20,
                 shares: shares(6),
                 last: sell
               }
             ]
    end

    test "deliveries add and remove shares" do
      transactions = [
        in_portfolio(:inbound_delivery, @thursday, 1, 20, 5),
        in_portfolio(:outbound_delivery, @friday, 1, 20, 2)
      ]

      assert shares_per_holding(Valuation.holdings(transactions, @friday)) == [{1, 20, shares(3)}]
    end

    test "a security transfer moves shares to the other portfolio" do
      transactions = [
        in_portfolio(:buy, @thursday, 1, 20, 10),
        in_portfolio(:security_transfer, @friday, 1, 20, 4, other_portfolio_id: 2)
      ]

      assert shares_per_holding(Valuation.holdings(transactions, @friday)) ==
               [{1, 20, shares(6)}, {2, 20, shares(4)}]
    end

    test "are kept apart per portfolio and security, and left out without shares" do
      transactions = [
        in_portfolio(:buy, @thursday, 1, 20, 1),
        in_portfolio(:buy, @thursday, 2, 20, 2),
        in_portfolio(:buy, @thursday, 1, 21, 3),
        in_portfolio(:sell, @friday, 1, 21, 3)
      ]

      assert shares_per_holding(Valuation.holdings(transactions, @friday)) ==
               [{1, 20, shares(1)}, {2, 20, shares(2)}]
    end

    test "count the transactions of the day and none after it" do
      transactions = [
        in_portfolio(:inbound_delivery, @friday, 1, 20, 1),
        in_portfolio(:inbound_delivery, @saturday, 1, 20, 2)
      ]

      assert Valuation.holdings(transactions, @thursday) == []
      assert shares_per_holding(Valuation.holdings(transactions, @friday)) == [{1, 20, shares(1)}]
    end

    test "take the largest of transactions at the same time as the last, as PP does" do
      small = in_portfolio(:buy, @friday, 1, 20, 10, amount: money(1_000))
      large = in_portfolio(:buy, @friday, 1, 20, 10, amount: money(1_200))

      for transactions <- [[small, large], [large, small]] do
        [holding] = Valuation.holdings(transactions, @friday)

        assert Valuation.value(holding, market([]), @friday) == money(2_400)
      end
    end

    test "do not change with dividends" do
      transactions = [
        in_portfolio(:inbound_delivery, @thursday, 1, 20, 5),
        transaction(:dividend, @friday,
          account_id: 10,
          security_id: 20,
          shares: shares(5),
          amount: money(1)
        )
      ]

      assert shares_per_holding(Valuation.holdings(transactions, @friday)) == [{1, 20, shares(5)}]
    end
  end

  describe "balances/2" do
    for {type, sign} <- [
          deposit: 1,
          removal: -1,
          buy: -1,
          sell: 1,
          dividend: 1,
          interest: 1,
          interest_charge: -1,
          tax: -1,
          tax_refund: 1,
          fee: -1,
          fee_refund: 1
        ] do
      test "#{type} books #{if sign > 0, do: "a credit", else: "a debit"}" do
        transactions = [transaction(unquote(type), @friday, account_id: 10, amount: money(100))]

        assert Valuation.balances(transactions, @friday) == %{10 => unquote(sign) * money(100)}
      end
    end

    test "add up per account" do
      transactions = [
        transaction(:deposit, @thursday, account_id: 10, amount: money(1_000)),
        in_portfolio(:buy, @friday, 1, 20, 10, account_id: 10, amount: money(900)),
        transaction(:deposit, @friday, account_id: 11, amount: money(5))
      ]

      assert Valuation.balances(transactions, @friday) == %{10 => money(100), 11 => money(5)}
    end

    test "a cash transfer moves the amount to the other account" do
      transfer =
        transaction(:cash_transfer, @friday,
          account_id: 10,
          other_account_id: 11,
          amount: money(500)
        )

      assert Valuation.balances([transfer], @friday) == %{10 => -money(500), 11 => money(500)}
    end

    test "a cash transfer into another currency credits its converted gross value" do
      unit = %TransactionUnit{
        type: :gross_value,
        amount: money(500),
        currency: "EUR",
        fx_amount: money(550),
        fx_currency: "USD"
      }

      transfer =
        transaction(:cash_transfer, @friday,
          account_id: 10,
          other_account_id: 11,
          amount: money(500),
          units: [unit]
        )

      assert Valuation.balances([transfer], @friday) == %{10 => -money(500), 11 => money(550)}
    end

    test "count no transaction after the day" do
      transactions = [transaction(:deposit, @saturday, account_id: 10, amount: money(1))]

      assert Valuation.balances(transactions, @friday) == %{}
    end
  end

  describe "value/3" do
    test "is shares times the last close before a day without a price" do
      market = market([{20, @friday, price(100)}])

      assert Valuation.value(holding(20, 10), market, @saturday) == money(1_000)
    end

    test "is shares times today's quote" do
      market = market([{20, @friday, price(100)}], quote_date: @saturday, quote: price(102))

      assert Valuation.value(holding(20, 10), market, @saturday) == money(1_020)
    end

    test "converts a foreign currency at the ECB rate of the day" do
      market = market([{21, @friday, price(110)}], rates: [{"USD", @friday, Decimal.new("1.10")}])

      assert Valuation.value(holding(21, 10), market, @friday) == money(1_000)
    end

    test "rounds half up to cents in the security's currency, as PP does" do
      market = market([{20, @friday, price(33.335)}])

      assert Valuation.value(holding(20, 3), market, @friday) == money(100.01)
    end

    test "multiplies to ten significant digits before rounding, as PP does" do
      market = market([{20, @friday, 123_456_789_460_000}])

      assert Valuation.value(holding(20, 1), market, @friday) == money(1_234_567.90)
    end

    test "takes the gross price per share of the last transaction without any price, as PP does" do
      fee = %TransactionUnit{type: :fee, amount: money(10), currency: "EUR"}

      transactions = [
        in_portfolio(:buy, @thursday, 1, 20, 2, amount: money(180)),
        in_portfolio(:buy, @friday, 1, 20, 4, amount: money(410), units: [fee])
      ]

      [holding] = Valuation.holdings(transactions, @friday)

      assert Valuation.value(holding, market([]), @friday) == money(600)
    end

    test "takes the price in the security's currency from the gross value of a foreign purchase" do
      unit = %TransactionUnit{
        type: :gross_value,
        amount: money(920),
        currency: "EUR",
        fx_amount: money(1_000),
        fx_currency: "USD"
      }

      buy = in_portfolio(:buy, @friday, 1, 21, 10, amount: money(920), units: [unit])
      market = market([], rates: [{"USD", @friday, Decimal.new("1.25")}])

      assert Valuation.value(holding(21, 10, buy), market, @friday) == money(800)
    end

    test "takes a price of 0 as none, as PP does" do
      buy = in_portfolio(:buy, @thursday, 1, 20, 10, amount: money(1_000))
      market = market([{20, @friday, 0}])

      assert Valuation.value(holding(20, 10, buy), market, @friday) == money(1_000)
    end

    test "is nothing without any price or transaction" do
      assert Valuation.value(holding(20, 10), market([]), @friday) == 0
    end
  end

  describe "price/3" do
    test "is the price a holding is valued at, in the security's currency" do
      market = market([{21, @friday, price(110)}], rates: [{"USD", @friday, Decimal.new("1.10")}])

      assert Valuation.price(holding(21, 10), market, @saturday) == price(110)
    end

    test "is the gross price per share of the last transaction without any price" do
      buy = in_portfolio(:buy, @friday, 1, 20, 4, amount: money(410))

      assert Valuation.price(holding(20, 4, buy), market([]), @friday) == price(102.5)
    end

    test "is nil without any price or transaction" do
      assert Valuation.price(holding(20, 10), market([]), @friday) == nil
    end
  end

  describe "price_per_share/2" do
    test "is a purchase's price before fees and taxes" do
      fee = %TransactionUnit{type: :fee, amount: money(10), currency: "EUR"}
      buy = in_portfolio(:buy, @friday, 1, 20, 4, amount: money(410), units: [fee])

      assert Valuation.price_per_share(buy, "EUR") == price(100)
    end

    test "is a sale's price before fees and taxes" do
      tax = %TransactionUnit{type: :tax, amount: money(20), currency: "EUR"}
      sale = in_portfolio(:sell, @friday, 1, 20, 4, amount: money(380), units: [tax])

      assert Valuation.price_per_share(sale, "EUR") == price(100)
    end

    test "counts a delivery as a purchase or a sale" do
      fee = %TransactionUnit{type: :fee, amount: money(2), currency: "EUR"}

      inbound =
        in_portfolio(:inbound_delivery, @friday, 1, 20, 2, amount: money(202), units: [fee])

      outbound =
        in_portfolio(:outbound_delivery, @friday, 1, 20, 2, amount: money(198), units: [fee])

      assert Valuation.price_per_share(inbound, "EUR") == price(100)
      assert Valuation.price_per_share(outbound, "EUR") == price(100)
    end

    test "is in the security's currency from the gross value of a foreign purchase" do
      unit = %TransactionUnit{
        type: :gross_value,
        amount: money(920),
        currency: "EUR",
        fx_amount: money(1_000),
        fx_currency: "USD"
      }

      buy = in_portfolio(:buy, @friday, 1, 21, 10, amount: money(920), units: [unit])

      assert Valuation.price_per_share(buy, "USD") == price(100)
    end

    test "is nil when the gross value is not known in the currency" do
      buy = in_portfolio(:buy, @friday, 1, 21, 10, amount: money(920))

      assert Valuation.price_per_share(buy, "USD") == nil
    end
  end

  describe "history/4" do
    setup do
      %{accounts: [%Account{id: 10, currency: "EUR"}, %Account{id: 11, currency: "USD"}]}
    end

    defp net_worth(transactions, accounts, market, date) do
      [%{date: ^date, net_worth: net_worth}] =
        Valuation.history(transactions, accounts, market, [date])

      net_worth
    end

    defp invested_capital(transactions, market \\ market([]), date) do
      [%{date: ^date, invested_capital: invested_capital}] =
        Valuation.history(transactions, [], market, [date])

      invested_capital
    end

    test "net worth adds the values of the holdings and the account balances", ctx do
      transactions = [
        transaction(:deposit, @thursday, account_id: 10, amount: money(1_000)),
        in_portfolio(:buy, @friday, 1, 20, 10, account_id: 10, amount: money(900))
      ]

      market = market([{20, @friday, price(95)}])

      assert net_worth(transactions, ctx.accounts, market, @friday) == money(1_050)
    end

    test "net worth converts account balances in a foreign currency", ctx do
      transactions = [
        transaction(:deposit, @friday, account_id: 11, currency: "USD", amount: money(110))
      ]

      market = market([], rates: [{"USD", @friday, Decimal.new("1.10")}])

      assert net_worth(transactions, ctx.accounts, market, @friday) == money(100)
    end

    test "net worth values a security held in several portfolios once, as PP does", ctx do
      transactions = [
        in_portfolio(:inbound_delivery, @friday, 1, 20, 1),
        in_portfolio(:inbound_delivery, @friday, 2, 20, 1)
      ]

      market = market([{20, @friday, price(0.015)}])

      assert net_worth(transactions, ctx.accounts, market, @friday) == 3
    end

    test "net worth takes the gross price of the last transaction up to each day without any price",
         ctx do
      transactions = [
        in_portfolio(:buy, @friday, 1, 20, 1, amount: money(110)),
        in_portfolio(:buy, @thursday, 1, 20, 1, amount: money(100))
      ]

      assert [%{net_worth: thursday}, %{net_worth: friday}] =
               Valuation.history(transactions, ctx.accounts, market([]), [@friday, @thursday])

      assert {thursday, friday} == {money(100), money(220)}
    end

    test "net worth takes the largest of transactions at the same time as the last", ctx do
      small = in_portfolio(:buy, @friday, 1, 20, 10, amount: money(1_000))
      large = in_portfolio(:buy, @friday, 2, 20, 10, amount: money(1_200))

      for transactions <- [[small, large], [large, small]] do
        assert net_worth(transactions, ctx.accounts, market([]), @friday) == money(2_400)
      end
    end

    test "gives each of the dates in order the transactions up to it and today's quote", ctx do
      transactions = [
        transaction(:deposit, @saturday, account_id: 10, amount: money(5)),
        in_portfolio(:inbound_delivery, @thursday, 1, 20, 10, amount: money(990))
      ]

      market = market([{20, @friday, price(100)}], quote_date: @saturday, quote: price(102))

      assert Valuation.history(transactions, ctx.accounts, market, [@saturday, @friday]) == [
               %{date: @friday, net_worth: money(1_000), invested_capital: money(990)},
               %{date: @saturday, net_worth: money(1_025), invested_capital: money(995)}
             ]
    end

    test "invested capital counts money from outside only" do
      transactions = [
        transaction(:deposit, ~D[2026-03-01], account_id: 10, amount: money(1_000)),
        in_portfolio(:buy, ~D[2026-03-02], 1, 20, 10, account_id: 10, amount: money(1_000)),
        in_portfolio(:inbound_delivery, ~D[2026-03-03], 1, 20, 5, amount: money(500)),
        transaction(:dividend, ~D[2026-03-04],
          account_id: 10,
          security_id: 20,
          shares: shares(15),
          amount: money(20)
        )
      ]

      assert invested_capital(transactions, ~D[2026-03-04]) == money(1_500)
    end

    test "invested capital goes down with removals and outbound deliveries" do
      transactions = [
        transaction(:deposit, @thursday, account_id: 10, amount: money(1_000)),
        transaction(:removal, @friday, account_id: 10, amount: money(300)),
        in_portfolio(:inbound_delivery, @thursday, 1, 20, 5, amount: money(500)),
        in_portfolio(:outbound_delivery, @friday, 1, 20, 2, amount: money(250))
      ]

      assert invested_capital(transactions, @friday) == money(950)
    end

    test "invested capital does not change with transfers between accounts or portfolios" do
      transactions = [
        transaction(:deposit, @thursday, account_id: 10, amount: money(1_000)),
        transaction(:cash_transfer, @friday,
          account_id: 10,
          other_account_id: 11,
          amount: money(400)
        ),
        in_portfolio(:inbound_delivery, @thursday, 1, 20, 5, amount: money(500)),
        in_portfolio(:security_transfer, @friday, 1, 20, 5,
          other_portfolio_id: 2,
          amount: money(520)
        )
      ]

      assert invested_capital(transactions, @friday) == money(1_500)
    end

    test "invested capital converts each transferal at the ECB rate of its own day" do
      transactions = [
        transaction(:deposit, @thursday, account_id: 11, currency: "USD", amount: money(110))
      ]

      market =
        market([],
          rates: [
            {"USD", @thursday, Decimal.new("1.10")},
            {"USD", @saturday, Decimal.new("1.25")}
          ]
        )

      assert invested_capital(transactions, market, @saturday) == money(100)
    end

    test "with a filter values only its portfolios and accounts", ctx do
      transactions = [
        transaction(:deposit, @thursday, account_id: 10, amount: money(1_000)),
        transaction(:deposit, @thursday, account_id: 11, currency: "USD", amount: money(7)),
        in_portfolio(:buy, @friday, 1, 20, 4, account_id: 10, amount: money(400)),
        in_portfolio(:buy, @friday, 2, 20, 1, account_id: 11, amount: money(100))
      ]

      filter = Filter.new([%Portfolio{id: 1}], [10], transactions)
      market = market([{20, @friday, price(110)}])

      assert [%{net_worth: net_worth}] =
               Valuation.history(transactions, ctx.accounts, market, [@friday], filter)

      assert net_worth == money(600 + 440)
    end

    test "with a filter, invested capital is the money its edge brings in or takes out", ctx do
      transactions = [
        transaction(:deposit, @thursday, account_id: 11, amount: money(1_000)),
        in_portfolio(:buy, @friday, 1, 20, 4, account_id: 11, amount: money(400)),
        in_portfolio(:outbound_delivery, @saturday, 1, 20, 1, amount: money(90))
      ]

      filter = Filter.new([%Portfolio{id: 1}], [], transactions)

      assert [%{invested_capital: friday}, %{invested_capital: saturday}] =
               Valuation.history(
                 transactions,
                 ctx.accounts,
                 market([]),
                 [@friday, @saturday],
                 filter
               )

      assert {friday, saturday} == {money(400), money(310)}
    end
  end

  describe "gross_dividends/3" do
    defp dividend(date, amount, attrs \\ []) do
      transaction(:dividend, date, [account_id: 10, security_id: 20, amount: amount] ++ attrs)
    end

    test "adds up the dividends of the days before taxes and fees" do
      units = [
        %TransactionUnit{type: :tax, amount: money(4), currency: "EUR"},
        %TransactionUnit{type: :fee, amount: money(1), currency: "EUR"},
        %TransactionUnit{type: :gross_value, amount: money(20), currency: "EUR"}
      ]

      transactions = [
        dividend(@thursday, money(15), units: units),
        dividend(@friday, money(30)),
        dividend(@saturday, money(99)),
        transaction(:interest, @friday, account_id: 10, amount: money(7))
      ]

      assert Valuation.gross_dividends(transactions, market([]), Date.range(@thursday, @friday)) ==
               money(50)
    end

    test "converts each dividend at the ECB rate of its day" do
      transactions = [
        dividend(@thursday, money(11), account_id: 11, currency: "USD"),
        dividend(@friday, money(25), account_id: 11, currency: "USD")
      ]

      market =
        market([],
          rates: [{"USD", @thursday, Decimal.new("1.10")}, {"USD", @friday, Decimal.new("1.25")}]
        )

      assert Valuation.gross_dividends(transactions, market, Date.range(@thursday, @friday)) ==
               money(30)
    end
  end
end
