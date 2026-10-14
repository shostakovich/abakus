defmodule AbakusWeb.BudgetLive.Rows do
  @moduledoc """
  The budget table's rows for the shown months: the uncategorised row while a shown month has activity or money in
  it, the groups with their categories and totals, and the income per payee.
  """

  alias Abakus.Budget.Month

  defstruct uncategorised: nil, groups: [], income: []

  @doc "Options: `income` (per `{payee, month}`)."
  def new(groups, months, opts) do
    cells = Map.new(for m <- months, row <- m.categories, do: {{row.category_id, m.month}, row})

    %__MODULE__{
      uncategorised: uncategorised(months),
      groups: Enum.map(groups, &group(&1, months, cells)),
      income: income(opts[:income], months)
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

  defp income(income, months) do
    shown = MapSet.new(months, fn %Month{month: month} -> month end)

    for {{payee, month}, amount} <- income, month in shown, amount != 0 do
      {payee, month, amount}
    end
    |> Enum.group_by(&elem(&1, 0), &{elem(&1, 1), elem(&1, 2)})
    |> Enum.map(fn {payee, amounts} -> %{payee: payee, amounts: Map.new(amounts)} end)
    |> Enum.sort_by(&{&1.payee == nil, &1.payee && String.downcase(&1.payee)})
  end
end
