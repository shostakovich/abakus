defmodule AbakusWeb.BudgetLive.Rows do
  @moduledoc """
  The budget table's rows for the shown months: the uncategorised row while a shown month has activity or money in
  it, and the groups with their categories and totals.
  """

  defstruct uncategorised: nil, groups: []

  def new(groups, months) do
    cells = Map.new(for m <- months, row <- m.categories, do: {{row.category_id, m.month}, row})

    %__MODULE__{
      uncategorised: uncategorised(months),
      groups: Enum.map(groups, &group(&1, months, cells))
    }
  end

  defp group(group, months, cells) do
    categories =
      for c <- group.categories do
        %{category: c, cells: Map.new(months, &{&1.month, cells[{c.id, &1.month}]})}
      end

    %{
      group: group,
      categories: categories,
      totals: Map.new(months, &{&1.month, totals(categories, &1.month)})
    }
  end

  defp totals(categories, month) do
    cells = Enum.map(categories, & &1.cells[month])

    %{
      assigned: sum(cells, :assigned),
      activity: sum(cells, :activity),
      available: sum(cells, :available)
    }
  end

  defp sum(cells, field), do: cells |> Enum.map(&Map.fetch!(&1, field)) |> Enum.sum()

  defp uncategorised(months) do
    if Enum.any?(months, &(&1.uncategorised.activity != 0 or &1.uncategorised.available != 0)),
      do: %{cells: Map.new(months, &{&1.month, &1.uncategorised})}
  end
end
