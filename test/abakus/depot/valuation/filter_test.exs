defmodule Abakus.Depot.Valuation.FilterTest do
  use ExUnit.Case, async: true

  import Abakus.Depot.PortfoliosFixtures, only: [money: 1, shares: 1]

  alias Abakus.Depot.Portfolios.{Portfolio, Transaction, TransactionUnit}
  alias Abakus.Depot.Valuation.Filter

  # Portfolio 1 settles against account 10 and holds security 20; portfolio 2 settles against
  # account 11; security 21 only portfolio 2 ever held.
  @portfolio %Portfolio{id: 1, reference_account_id: 10}

  defp transaction(type, attrs) do
    struct!(
      %Transaction{
        type: type,
        date_time: ~N[2026-10-02 12:00:00],
        amount: money(100),
        units: []
      },
      attrs
    )
  end

  defp history do
    [
      transaction(:buy, portfolio_id: 1, account_id: 10, security_id: 20, shares: shares(1)),
      transaction(:buy, portfolio_id: 2, account_id: 11, security_id: 21, shares: shares(1))
    ]
  end

  defp with_account, do: Filter.new([@portfolio], [10], history())
  defp without_account, do: Filter.new([@portfolio], [], history())

  defp dividend(type, account_id, security_id),
    do: transaction(type, account_id: account_id, security_id: security_id)

  defp cash_transfer(from, to),
    do: transaction(:cash_transfer, account_id: from, other_account_id: to)

  describe "all/0" do
    test "counts deposits and inbound deliveries as money in, removals and outbound ones as out" do
      assert Filter.flows(Filter.all(), transaction(:deposit, account_id: 10)) ==
               [{:inbound, money(100)}]

      assert Filter.flows(Filter.all(), transaction(:inbound_delivery, portfolio_id: 1)) ==
               [{:inbound, money(100)}]

      assert Filter.flows(Filter.all(), transaction(:removal, account_id: 10)) ==
               [{:outbound, money(100)}]

      assert Filter.flows(Filter.all(), transaction(:outbound_delivery, portfolio_id: 1)) ==
               [{:outbound, money(100)}]
    end

    test "keeps transfers as transfers" do
      assert Filter.flows(Filter.all(), cash_transfer(10, 11)) ==
               [{:transfer_out, money(100)}, {:transfer_in, money(100)}]

      transfer = transaction(:security_transfer, portfolio_id: 1, other_portfolio_id: 2)

      assert Filter.flows(Filter.all(), transfer) ==
               [{:transfer_out, money(100)}, {:transfer_in, money(100)}]
    end

    test "counts no money in or out for what happens inside" do
      for transaction <- history() ++ [transaction(:sell, portfolio_id: 1, account_id: 10)],
          do: assert(Filter.flows(Filter.all(), transaction) == [])

      for type <- [:dividend, :interest, :interest_charge, :tax, :tax_refund, :fee, :fee_refund],
          do: assert(Filter.flows(Filter.all(), dividend(type, 10, 99)) == [])
    end

    test "includes every portfolio and account" do
      assert Filter.portfolio?(Filter.all(), 1)
      assert Filter.account?(Filter.all(), 10)
      refute Filter.account?(Filter.all(), nil)
    end
  end

  describe "new/3" do
    test "includes the given portfolios and accounts only" do
      assert Filter.portfolio?(with_account(), 1)
      refute Filter.portfolio?(with_account(), 2)
      assert Filter.account?(with_account(), 10)
      refute Filter.account?(with_account(), 11)
      refute Filter.account?(without_account(), 10)
    end

    test "a purchase from an account outside brings the shares in, a sale into one takes them out" do
      buy = transaction(:buy, portfolio_id: 1, account_id: 11)
      sell = transaction(:sell, portfolio_id: 1, account_id: 11)

      assert Filter.flows(with_account(), buy) == [{:inbound, money(100)}]
      assert Filter.flows(with_account(), sell) == [{:outbound, money(100)}]
      assert Filter.flows(without_account(), hd(history())) == [{:inbound, money(100)}]
    end

    test "a purchase by a portfolio outside takes the money out, a sale by one brings it in" do
      buy = transaction(:buy, portfolio_id: 2, account_id: 10)
      sell = transaction(:sell, portfolio_id: 2, account_id: 10)

      assert Filter.flows(with_account(), buy) == [{:outbound, money(100)}]
      assert Filter.flows(with_account(), sell) == [{:inbound, money(100)}]
    end

    test "a purchase or sale inside counts no money in or out" do
      assert Filter.flows(with_account(), transaction(:sell, portfolio_id: 1, account_id: 10)) ==
               []
    end

    test "a transfer across the edge is money in or out" do
      assert Filter.flows(with_account(), cash_transfer(10, 11)) == [{:outbound, money(100)}]
      assert Filter.flows(with_account(), cash_transfer(11, 10)) == [{:inbound, money(100)}]

      out = transaction(:security_transfer, portfolio_id: 1, other_portfolio_id: 2)
      into = transaction(:security_transfer, portfolio_id: 2, other_portfolio_id: 1)

      assert Filter.flows(with_account(), out) == [{:outbound, money(100)}]
      assert Filter.flows(with_account(), into) == [{:inbound, money(100)}]
    end

    test "a dividend, tax or fee of a security the portfolios never held is money in or out" do
      for type <- [:dividend, :tax_refund, :fee_refund],
          do:
            assert(
              Filter.flows(with_account(), dividend(type, 10, 21)) == [
                {:inbound, money(100)}
              ]
            )

      for type <- [:tax, :fee],
          do:
            assert(
              Filter.flows(with_account(), dividend(type, 10, 21)) == [
                {:outbound, money(100)}
              ]
            )
    end

    test "a dividend, tax or fee of a held security or without one stays inside" do
      for type <- [:dividend, :tax, :fee, :interest, :interest_charge],
          security_id <- [20, nil],
          do: assert(Filter.flows(with_account(), dividend(type, 10, security_id)) == [])
    end

    test "a dividend on the reference account outside goes out at once, a tax or fee comes in" do
      assert Filter.flows(without_account(), dividend(:dividend, 10, 20)) ==
               [{:outbound, money(100)}]

      assert Filter.flows(without_account(), dividend(:tax, 10, 20)) ==
               [{:inbound, money(100)}]

      assert Filter.flows(without_account(), dividend(:dividend, 10, 21)) == []
      assert Filter.flows(without_account(), dividend(:dividend, 11, 20)) == []
      assert Filter.flows(without_account(), dividend(:interest, 10, nil)) == []
    end

    test "counts nothing of other portfolios and accounts" do
      for transaction <- [
            transaction(:deposit, account_id: 11),
            transaction(:inbound_delivery, portfolio_id: 2),
            transaction(:buy, portfolio_id: 2, account_id: 11),
            cash_transfer(11, 12)
          ],
          do: assert(Filter.flows(with_account(), transaction) == [])
    end
  end

  describe "view/2" do
    defp fee_unit, do: %TransactionUnit{type: :fee, amount: money(1)}

    test "keeps every transaction of all portfolios and accounts as it is" do
      buy = hd(history())

      assert Filter.view(Filter.all(), buy) == [buy]
    end

    test "turns a purchase from an account outside into an inbound delivery, a sale into an outbound one" do
      buy =
        transaction(:buy, portfolio_id: 1, account_id: 12, security_id: 20, units: [fee_unit()])

      sell = %{buy | type: :sell}

      assert Filter.view(with_account(), buy) == [
               %{buy | type: :inbound_delivery, account_id: nil}
             ]

      assert Filter.view(with_account(), sell) == [
               %{sell | type: :outbound_delivery, account_id: nil}
             ]
    end

    test "turns a purchase by a portfolio outside into a removal, a sale into a deposit" do
      buy =
        transaction(:buy, portfolio_id: 2, account_id: 10, security_id: 21, units: [fee_unit()])

      seen = %{buy | portfolio_id: nil, security_id: nil, shares: nil, units: []}

      assert Filter.view(with_account(), buy) == [%{seen | type: :removal}]
      assert Filter.view(with_account(), %{buy | type: :sell}) == [%{seen | type: :deposit}]
    end

    test "turns a transfer across the edge into a delivery, deposit or removal" do
      out =
        transaction(:security_transfer, portfolio_id: 1, other_portfolio_id: 2, shares: shares(1))

      into = %{out | portfolio_id: 2, other_portfolio_id: 1}

      assert Filter.view(with_account(), out) ==
               [%{out | type: :outbound_delivery, other_portfolio_id: nil}]

      assert Filter.view(with_account(), into) ==
               [%{into | type: :inbound_delivery, portfolio_id: 1, other_portfolio_id: nil}]

      assert [%{type: :removal, account_id: 10, other_account_id: nil, units: []}] =
               Filter.view(with_account(), cash_transfer(10, 11))

      assert [%{type: :deposit, account_id: 10, other_account_id: nil, amount: 10_000, units: []}] =
               Filter.view(with_account(), cash_transfer(11, 10))
    end

    test "turns a dividend, tax or fee of a security never held into a deposit or removal" do
      dividend = dividend(:dividend, 10, 21)
      tax = dividend(:tax, 10, 21)

      assert Filter.view(with_account(), dividend) ==
               [%{dividend | type: :deposit, security_id: nil}]

      assert Filter.view(with_account(), tax) == [%{tax | type: :removal, security_id: nil}]

      assert Filter.view(with_account(), dividend(:dividend, 10, 20)) == [
               dividend(:dividend, 10, 20)
             ]
    end

    test "pays out a dividend on the reference account outside at once, and pays in a tax" do
      dividend = dividend(:dividend, 10, 20)
      tax = dividend(:tax, 10, 20)
      plain = %{dividend | security_id: nil}

      assert Filter.view(without_account(), dividend) == [dividend, %{plain | type: :removal}]
      assert Filter.view(without_account(), tax) == [tax, %{plain | type: :deposit}]
    end

    test "leaves out what happens outside" do
      assert Filter.view(with_account(), transaction(:deposit, account_id: 11)) == []
      assert Filter.view(with_account(), Enum.at(history(), 1)) == []
      assert Filter.view(without_account(), dividend(:dividend, 10, 21)) == []
    end
  end
end
