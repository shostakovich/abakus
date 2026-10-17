defmodule Abakus.Depot.WealthTest do
  use ExUnit.Case, async: true

  alias Abakus.Depot.{Period, Wealth}

  @today ~D[2026-10-17]
  @depot_first ~D[2020-03-02]
  @budget_first ~D[2025-06-13]

  # The Depot's chart as `Portfolios.overview/3` draws it, negative so it tells from the budget's.
  defp overview(period, depot_first) do
    range = Period.range(period, @today, depot_first)

    %{
      first_day: depot_first,
      chart: for(date <- Period.chart_days(range), do: %{date: date, net_worth: -cents(date)})
    }
  end

  defp budget_net_worth do
    test = self()

    fn range ->
      send(test, {:budget_range, range})
      Enum.map(range, &{&1, cents(&1)})
    end
  end

  defp cents(date), do: Date.to_gregorian_days(date)

  defp wealth(period, depot_first, budget_first),
    do:
      Wealth.of_budget_owner(
        overview(period, depot_first),
        budget_first,
        budget_net_worth(),
        period,
        @today
      )

  test "reaches back to the Depot's first day and draws its value until the budget starts" do
    wealth = wealth(:max, @depot_first, @budget_first)

    dates = Enum.map(wealth.chart, & &1.date)
    assert dates == Period.chart_days(Date.range(@depot_first, @today))
    assert hd(dates) == @depot_first

    for %{date: date, net_worth: net_worth} <- wealth.chart do
      expected = if Date.before?(date, @budget_first), do: -cents(date), else: cents(date)
      assert net_worth == expected
    end

    assert Enum.all?(wealth.chart, &(&1.invested_capital == nil and &1.benchmark == nil))
    assert wealth.depot_only == {:before, @budget_first}
    assert_received {:budget_range, budget_range}
    assert budget_range == Date.range(@budget_first, @today)
  end

  test "keeps net worth and its change the budget's" do
    wealth = wealth(:max, @depot_first, @budget_first)

    assert wealth.net_worth == cents(@today)
    assert wealth.net_worth_yesterday == cents(Date.add(@today, -1))
  end

  test "draws only the budget when the period starts after the budget's first day" do
    wealth = wealth(:one_year, @depot_first, @budget_first)

    assert Enum.map(wealth.chart, & &1.date) == Enum.to_list(Date.range(~D[2025-10-17], @today))
    assert Enum.all?(wealth.chart, &(&1.net_worth == cents(&1.date)))
    assert wealth.depot_only == nil
  end

  test "draws only the Depot while the budget has no transactions" do
    wealth = wealth(:max, @depot_first, nil)

    assert Enum.map(wealth.chart, & &1.date) ==
             Period.chart_days(Date.range(@depot_first, @today))

    assert Enum.all?(wealth.chart, &(&1.net_worth == -cents(&1.date)))
    assert wealth.depot_only == :all
    assert wealth.net_worth == cents(@today)
    assert_received {:budget_range, budget_range}
    assert budget_range == Date.range(Date.add(@today, -1), @today)
  end

  test "says nothing of the Depot while neither it nor the budget has transactions" do
    wealth = wealth(:max, nil, nil)

    assert Enum.map(wealth.chart, & &1.date) == [@today]
    assert wealth.depot_only == nil
  end

  for {situation, depot_first} <- [
        "the Depot starts after the budget": ~D[2025-08-01],
        "the Depot has no transactions": nil
      ] do
    test "draws only the budget from its first day when #{situation}" do
      wealth = wealth(:max, unquote(Macro.escape(depot_first)), @budget_first)

      assert Enum.map(wealth.chart, & &1.date) ==
               Period.chart_days(Date.range(@budget_first, @today))

      assert Enum.all?(wealth.chart, &(&1.net_worth == cents(&1.date)))
      assert wealth.depot_only == nil
    end
  end
end
