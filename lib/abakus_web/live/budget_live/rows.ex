defmodule AbakusWeb.BudgetLive.Rows do
  @moduledoc """
  The budget table's rows for the shown months: the uncategorised row while a shown month has activity or money in
  it, the groups with their categories and totals (hidden ones left out), and the income per payee. A filter keeps
  the categories in its state in the focus month and the groups that have one; income shows only unfiltered. A
  snoozed target counts as done, so its category is not underfunded.
  `counts` are the focus month's overspent, underfunded and snoozed categories, whatever the filter.
  """

  alias Abakus.Budget.{CategoryMonth, Month}

  defstruct uncategorised: nil, groups: [], income: [], counts: %{}

  @filters [:all, :overspent, :underfunded, :overfunded, :available, :snoozed]

  def filters, do: @filters

  @doc "Options: `focus` (the focus month), `filter` (one of `filters/0`), `income` (per `{payee, month}`)."
  def new(groups, months, opts) do
    focus = opts[:focus]
    filter = opts[:filter]
    cells = Map.new(for m <- months, row <- m.categories, do: {{row.category_id, m.month}, row})
    uncategorised = uncategorised(months)
    groups = for g <- groups, not g.hidden, do: group(g, months, cells)

    %__MODULE__{
      uncategorised:
        if(uncategorised && matches?(uncategorised.cells[focus], filter), do: uncategorised),
      groups: filter_groups(groups, focus, filter),
      income: if(filter == :all, do: income(opts[:income], months), else: []),
      counts: counts([uncategorised | Enum.flat_map(groups, & &1.categories)], focus)
    }
  end

  defp group(group, months, cells) do
    categories =
      for c <- group.categories, not c.hidden do
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

  defp filter_groups(groups, _focus, :all), do: groups

  defp filter_groups(groups, focus, filter) do
    for group <- groups,
        categories = Enum.filter(group.categories, &matches?(&1.cells[focus], filter)),
        categories != [],
        do: %{group | categories: categories}
  end

  defp matches?(%CategoryMonth{}, :all), do: true
  defp matches?(%CategoryMonth{available: available}, :overspent), do: available < 0
  defp matches?(%CategoryMonth{} = row, :underfunded), do: row.underfunded > 0 and not row.snoozed
  defp matches?(%CategoryMonth{available: available}, :available), do: available > 0
  defp matches?(%CategoryMonth{snoozed: snoozed}, :snoozed), do: snoozed

  defp matches?(%CategoryMonth{} = row, :overfunded),
    do: row.target != nil and row.underfunded == 0 and row.assigned > row.needed

  defp counts(rows, focus) do
    cells = for row when row != nil <- rows, do: row.cells[focus]

    %{
      overspent: Enum.count(cells, &matches?(&1, :overspent)),
      underfunded: Enum.count(cells, &matches?(&1, :underfunded)),
      snoozed: Enum.count(cells, &matches?(&1, :snoozed))
    }
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
