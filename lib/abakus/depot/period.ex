defmodule Abakus.Depot.Period do
  @moduledoc """
  A period up to today, as the overview offers it for its chart and returns: six months, the year
  to date, one year, or everything since the first transaction (`:max`); the performance screen
  also offers one month and three years, the price chart of a security five years.
  """

  @type t ::
          :one_month | :six_months | :year_to_date | :one_year | :three_years | :five_years | :max

  @doc """
  The days of `period` up to `today`, from `first_day` on at the earliest, such as the day of the
  first transaction; only today without a `first_day` up to today.
  """
  def range(period, today, first_day) do
    first_day = first_day(first_day, today)

    Date.range(Enum.max([start(period, today) || first_day, first_day], Date), today)
  end

  @doc """
  The days of `period` up to `today` over which returns are computed, as PP's reporting periods:
  the first is the reference day, whose closing value the returns start from. The year to date
  starts from 31 December, `:max` from the day before the first transaction, `first_day`; no
  period earlier than that day, as nothing changes before.
  """
  def interval(period, today, first_day) do
    before_first = first_day |> first_day(today) |> Date.add(-1)

    Date.range(
      Enum.max([reference_day(period, today) || before_first, before_first], Date),
      today
    )
  end

  defp first_day(nil, today), do: today
  defp first_day(first_day, today), do: Enum.min([first_day, today], Date)

  defp reference_day(:year_to_date, today), do: Date.new!(today.year - 1, 12, 31)
  defp reference_day(period, today), do: start(period, today)

  defp start(:one_month, today), do: Date.shift(today, month: -1)
  defp start(:six_months, today), do: Date.shift(today, month: -6)
  defp start(:year_to_date, today), do: Date.new!(today.year, 1, 1)
  defp start(:one_year, today), do: Date.shift(today, year: -1)
  defp start(:three_years, today), do: Date.shift(today, year: -3)
  defp start(:five_years, today), do: Date.shift(today, year: -5)
  defp start(:max, _today), do: nil

  @doc """
  The days of `range` a chart shows: all of them for up to a year. Beyond, the first and every
  seventh counting back from the last; every day of many years would outnumber the chart's pixels
  and swell the data sent to the browser.
  """
  def chart_days(%Date.Range{first: first, last: last} = range) do
    if Date.before?(first, Date.shift(last, year: -1)),
      do: Enum.uniq([first | Enum.reverse(Date.range(last, first, -7))]),
      else: Enum.to_list(range)
  end
end
