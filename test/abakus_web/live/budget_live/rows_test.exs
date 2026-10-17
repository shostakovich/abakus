defmodule AbakusWeb.BudgetLive.RowsTest do
  use ExUnit.Case, async: true

  alias Abakus.Budget.{CategoryMonth, Month}
  alias Abakus.Categories.{Category, CategoryGroup}
  alias AbakusWeb.BudgetLive.Rows

  @oct ~D[2026-10-01]
  @nov ~D[2026-11-01]

  @groceries %Category{id: 1, name: "🛒 Lebensmittel"}
  @fuel %Category{id: 2, name: "⛽ Tanken"}
  @old %Category{id: 3, name: "Alt", hidden: true}
  @rent %Category{id: 4, name: "🏠 Miete"}
  @daily %CategoryGroup{id: 10, name: "Alltag", categories: [@groceries, @fuel, @old]}
  @housing %CategoryGroup{id: 11, name: "Wohnen", categories: [@rent]}
  @gone %CategoryGroup{id: 12, name: "Weg", hidden: true, categories: [%Category{id: 5}]}

  # Every category has a row in every month, as `Abakus.Budget` computes them.
  defp month(month, rows, uncategorised \\ %{}) do
    Month.new(
      month,
      0,
      struct!(CategoryMonth, Map.merge(%{month: month}, uncategorised)),
      for(
        id <- 1..5,
        do: struct!(CategoryMonth, Map.merge(%{category_id: id, month: month}, rows[id] || %{}))
      )
    )
  end

  defp rows(months), do: Rows.new([@daily, @housing, @gone], months)

  test "lists the groups and categories, those hidden in YNAB too, with their months and the groups' totals" do
    rows =
      rows([
        month(@oct, %{
          1 => %{assigned: 1_000, available: 1_000},
          2 => %{activity: -300, available: -300},
          3 => %{assigned: 99}
        }),
        month(@nov, %{1 => %{assigned: 500, available: 1_500}})
      ])

    assert [
             %{group: @daily, categories: [groceries, fuel, old]},
             %{group: @housing},
             %{group: @gone}
           ] =
             rows.groups

    assert old.category == @old
    assert groceries.category == @groceries
    assert %CategoryMonth{assigned: 500, available: 1_500} = groceries.cells[@nov]
    assert %CategoryMonth{available: -300} = fuel.cells[@oct]

    assert hd(rows.groups).totals == %{
             @oct => %{assigned: 1_099, activity: -300, available: 700},
             @nov => %{assigned: 500, activity: 0, available: 1_500}
           }
  end

  test "has the uncategorised row while a shown month has activity or money in it" do
    assert rows([month(@oct, %{}), month(@nov, %{})]).uncategorised == nil

    assert %{cells: %{@nov => %CategoryMonth{available: -999}}} =
             rows([month(@oct, %{}), month(@nov, %{}, %{activity: -999, available: -999})]).uncategorised
  end
end
