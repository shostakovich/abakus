defmodule Abakus.Bookkeeping.Depreciation do
  @moduledoc """
  What a fixed asset counts for in the EÜR of a year. Up to the low-value limit of 800 € net it is expensed at once
  in its purchase year. Above it, it is depreciated straight-line by month over its useful life, from the month of
  purchase up to and including the month of its disposal; each year gets what the months up to its end come to less
  what the years before had, so that the years add up to the net amount to the cent.

  A disposal counts in its own year: the book value it leaves as an expense, its amount as income.
  """

  alias Abakus.Bookkeeping.{Disposal, FixedAsset}

  @low_value_limit 80_000

  @doc "Whether a net amount in cents is expensed at once."
  def low_value?(net) when is_integer(net), do: net <= @low_value_limit

  @doc """
  What the asset, with its disposal loaded, counts for in `year`: `write_off` in cents (the whole net amount in the
  purchase year of a low-value one, else the year's depreciation), and, in the year of its disposal, the
  `disposal` and the `remaining` book value it leaves.
  """
  def year(%FixedAsset{disposal: disposal} = asset, year) do
    disposal = if disposal && disposal.date.year == year, do: disposal

    %{
      low_value?: low_value?(asset.net),
      write_off: written_off(asset, month(year, 12)) - written_off(asset, month(year - 1, 12)),
      disposal: disposal,
      remaining: if(disposal, do: book_value(asset, disposal.date), else: 0)
    }
  end

  @doc "The book value in cents at the end of the month of `date`, before a disposal in that month."
  def book_value(%FixedAsset{} = asset, %Date{} = date),
    do: asset.net - written_off(asset, month(date.year, date.month))

  @doc "The book value in cents on `date`: none once the asset has left the register."
  def current_value(%FixedAsset{disposal: disposal} = asset, %Date{} = date) do
    if disposal && Date.compare(disposal.date, date) != :gt,
      do: 0,
      else: book_value(asset, date)
  end

  defp written_off(asset, month) do
    months = counted_months(asset, month)

    cond do
      months <= 0 -> 0
      low_value?(asset.net) -> asset.net
      true -> share(asset.net, min(months, life(asset)), life(asset))
    end
  end

  defp elapsed(asset, month),
    do: month - month(asset.purchased_on.year, asset.purchased_on.month) + 1

  defp counted_months(%FixedAsset{disposal: %Disposal{date: date}} = asset, month),
    do: min(elapsed(asset, month), elapsed(asset, month(date.year, date.month)))

  defp counted_months(%FixedAsset{disposal: nil} = asset, month), do: elapsed(asset, month)

  defp life(%FixedAsset{useful_life: years}), do: years * 12

  defp month(year, month), do: year * 12 + month - 1

  defp share(net, months, life), do: div(2 * net * months + life, 2 * life)
end
