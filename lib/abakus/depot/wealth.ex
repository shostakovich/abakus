defmodule Abakus.Depot.Wealth do
  @moduledoc """
  What Vermögen shows the budget owner (ADR 0020): on each day the Ledger's net worth, the money in all their
  accounts, plus the value of all their holdings, from the earlier of the budget's and the Depot's first day.
  """

  alias Abakus.Depot.{Period, Portfolios}
  alias Abakus.Ledger
  alias Abakus.Users.Scope

  @doc """
  The budget owner's wealth for `period` up to `today`, amounts in euro cents: `net_worth` today and
  `net_worth_yesterday`, and the `chart` on the days a chart shows of the period. `depot_first` is the day of the
  Depot's first transaction, nil without any. An account the Depot uses counts while it holds money, closed or not,
  as the Depot shows it (`Ledger.net_worth/3`).
  """
  def of_budget_owner(%Scope{} = scope, depot_first, period, today) do
    kept = Enum.map(Portfolios.list_accounts(scope), & &1.id)

    range =
      Period.range(period, today, earliest(depot_first, Ledger.first_open_date(scope, kept)))

    chart_days = Period.chart_days(range)
    yesterday = Date.add(today, -1)

    money =
      scope
      |> Ledger.net_worth(Date.range(Enum.min([range.first, yesterday], Date), today), kept)
      |> Map.new()

    holdings = Portfolios.holdings_value(scope, Enum.uniq([yesterday | chart_days]))
    net_worth = fn date -> money[date] + holdings[date] end

    %{
      net_worth: net_worth.(today),
      net_worth_yesterday: net_worth.(yesterday),
      chart:
        for(
          date <- chart_days,
          do: %{date: date, net_worth: net_worth.(date), invested_capital: nil, benchmark: nil}
        )
    }
  end

  defp earliest(nil, day), do: day
  defp earliest(day, nil), do: day
  defp earliest(first, second), do: Enum.min([first, second], Date)
end
