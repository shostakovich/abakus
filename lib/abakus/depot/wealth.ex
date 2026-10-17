defmodule Abakus.Depot.Wealth do
  @moduledoc """
  What Vermögen shows the budget owner: net worth is the budget's, all its open accounts. The chart
  reaches back to the Depot's first transaction when the Depot started earlier than the budget, and
  draws the Depot's net worth on the days before the budget's first open date.
  """

  alias Abakus.Depot.Period

  @doc """
  The budget owner's wealth for `period` up to `today`, amounts in euro cents:

  - `net_worth` today and `net_worth_yesterday`, the budget's
  - `chart`: on the days a chart shows of the period from the earlier of the Depot's and the
    budget's first day on, the Depot's net worth from `overview`'s chart before `budget_first`, the
    budget's from then on
  - `depot_only`: the chart's days that show only the Depot: `{:before, budget_first}`, `:all`
    when only the Depot has transactions yet, nil for none

  `overview` is `Portfolios.overview/3` of the same `period` and `today`, `budget_first` the
  budget's first open date, nil without one, and `budget_net_worth` gives the budget's net worth on
  each day of a date range as `[{date, cents}]`, as `Ledger.net_worth/2`.
  """
  def of_budget_owner(overview, budget_first, budget_net_worth, period, today) do
    budget_first = budget_first && Enum.min([budget_first, today], Date)
    range = Period.range(period, today, earliest(overview.first_day, budget_first))
    budget_from = if budget_first, do: Enum.max([range.first, budget_first], Date), else: today

    days =
      budget_net_worth.(Date.range(Enum.min([budget_from, Date.add(today, -1)], Date), today))

    [{_yesterday, net_worth_yesterday}, {_today, net_worth}] = Enum.take(days, -2)
    budget = Map.new(days)
    depot = Map.new(overview.chart, &{&1.date, &1.net_worth})
    chart_days = Period.chart_days(range)

    %{
      net_worth: net_worth,
      net_worth_yesterday: net_worth_yesterday,
      chart:
        for date <- chart_days do
          cents =
            if depot_day?(date, budget_first),
              do: Map.fetch!(depot, date),
              else: Map.fetch!(budget, date)

          %{date: date, net_worth: cents, invested_capital: nil, benchmark: nil}
        end,
      depot_only: depot_only(hd(chart_days), budget_first, overview.first_day)
    }
  end

  defp earliest(nil, day), do: day
  defp earliest(day, nil), do: day
  defp earliest(first, second), do: Enum.min([first, second], Date)

  defp depot_day?(_date, nil), do: true
  defp depot_day?(date, budget_first), do: Date.before?(date, budget_first)

  defp depot_only(_first, nil, nil), do: nil
  defp depot_only(_first, nil, _depot_first), do: :all

  defp depot_only(first, budget_first, _depot_first),
    do: if(Date.before?(first, budget_first), do: {:before, budget_first})
end
