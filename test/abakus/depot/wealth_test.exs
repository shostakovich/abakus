defmodule Abakus.Depot.WealthTest do
  use Abakus.DataCase

  import Abakus.Depot.{PortfoliosFixtures, SecuritiesFixtures}
  import Abakus.DomainFixtures, only: [budget_scope: 0]

  alias Abakus.Depot.{Period, Wealth}
  alias Abakus.{DomainFixtures, Ledger}

  @today ~D[2026-10-17]
  @depot_first ~D[2020-03-02]
  @repriced ~D[2023-01-02]

  setup do
    scope = budget_scope()
    security = security_fixture(quote_feed: :manual)
    price_fixture(security, @depot_first, price(100), :manual)
    price_fixture(security, @repriced, price(120), :manual)

    portfolio = portfolio_fixture(scope, %{name: "Broker"})
    cash = cash_account_fixture(portfolio, account_fixture(scope, %{name: "Broker cash"}))
    holding = [portfolio_id: portfolio.id, security_id: security.id]

    transaction_fixture(
      scope,
      @depot_first,
      [type: :inbound_delivery, shares: shares(10)] ++ holding
    )

    transaction_fixture(scope, ~D[2021-05-03],
      type: :deposit,
      account_id: cash.id,
      amount: money(1_000)
    )

    transaction_fixture(
      scope,
      ~D[2021-06-01],
      [type: :buy, account_id: cash.id, shares: shares(5), amount: money(500)] ++ holding
    )

    retired = portfolio_fixture(scope, %{name: "Old", retired: true})
    old_cash = cash_account_fixture(retired, account_fixture(scope, %{name: "Old cash"}))

    transaction_fixture(scope, ~D[2022-01-03],
      type: :deposit,
      account_id: old_cash.id,
      amount: money(50)
    )

    {:ok, old_cash} = Ledger.update_account(scope, old_cash, %{closed: true})

    checking = DomainFixtures.account_fixture(name: "Checking")
    booking(checking, ~D[2025-06-13], 2_000)
    booking(checking, ~D[2025-07-01], -300)

    savings = DomainFixtures.account_fixture(name: "Old savings", kind: :savings)
    booking(savings, ~D[2023-03-01], 400)
    booking(savings, ~D[2024-03-01], -400)
    {:ok, savings} = Ledger.update_account(scope, savings, %{closed: true})

    gone = DomainFixtures.account_fixture(name: "Gone")
    booking(gone, ~D[2024-01-01], 700)
    {:ok, _gone} = Ledger.update_account(scope, gone, %{closed: true})

    %{scope: scope, counted: [cash, old_cash, checking, savings]}
  end

  defp booking(account, date, euros),
    do:
      DomainFixtures.transaction_fixture(account_id: account.id, date: date, amount: money(euros))

  defp holdings_value(date) do
    shares = if Date.before?(date, ~D[2021-06-01]), do: 10, else: 15
    price = if Date.before?(date, @repriced), do: 100, else: 120
    money(shares * price)
  end

  test "on every day of the chart, before the budget's first day too, is the accounts' money plus the holdings",
       %{scope: scope, counted: counted} do
    wealth = Wealth.of_budget_owner(scope, @depot_first, :max, @today)

    assert Enum.map(wealth.chart, & &1.date) ==
             Period.chart_days(Date.range(@depot_first, @today))

    for %{date: date, net_worth: net_worth} <- wealth.chart do
      balances = Enum.sum_by(counted, &Ledger.balance(scope, &1, date))
      assert net_worth == balances + holdings_value(date), "on #{date}"
    end

    assert hd(wealth.chart).net_worth == money(1_000)
  end

  test "counts each account once and the holdings without their cash", %{scope: scope} do
    wealth = Wealth.of_budget_owner(scope, @depot_first, :max, @today)

    assert wealth.net_worth == money(15 * 120 + 500 + 50 + 1_700)
    assert wealth.net_worth_yesterday == wealth.net_worth
  end

  test "starts with the budget when it starts before the Depot", %{scope: scope} do
    DomainFixtures.transaction_fixture(
      account_id: DomainFixtures.account_fixture(name: "Cash", kind: :cash).id,
      date: ~D[2019-01-07],
      amount: money(20)
    )

    wealth = Wealth.of_budget_owner(scope, @depot_first, :max, @today)

    assert %{date: ~D[2019-01-07], net_worth: 2_000} = hd(wealth.chart)
  end

  test "shows the period's days only", %{scope: scope} do
    wealth = Wealth.of_budget_owner(scope, @depot_first, :one_year, @today)

    assert Enum.map(wealth.chart, & &1.date) ==
             Enum.to_list(Date.range(~D[2025-10-17], @today))

    assert Enum.all?(wealth.chart, &(&1.invested_capital == nil and &1.benchmark == nil))
  end
end
