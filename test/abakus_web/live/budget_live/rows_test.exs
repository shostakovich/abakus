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

  defp rows(months, opts \\ []) do
    Rows.new([@daily, @housing, @gone], months,
      focus: Keyword.get(opts, :focus, @oct),
      filter: Keyword.get(opts, :filter, :all),
      income: Keyword.get(opts, :income, %{})
    )
  end

  defp names(%Rows{groups: groups}),
    do: for(%{categories: categories} <- groups, %{category: c} <- categories, do: c.name)

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

  test "a filter keeps the categories in that state in the focus month and the groups that have one; a snoozed target is not underfunded" do
    months = [
      month(@oct, %{
        1 => %{available: 2_000, assigned: 3_000, needed: 1_000, target: %{}},
        2 => %{available: -300},
        4 => %{underfunded: 500, snoozed: true}
      }),
      month(@nov, %{2 => %{available: 100, underfunded: 50}})
    ]

    assert names(rows(months, filter: :overspent)) == ["⛽ Tanken"]
    assert names(rows(months, filter: :overspent, focus: @nov)) == []
    assert names(rows(months, filter: :available)) == ["🛒 Lebensmittel"]
    assert names(rows(months, filter: :overfunded)) == ["🛒 Lebensmittel"]
    assert names(rows(months, filter: :underfunded)) == []
    assert names(rows(months, filter: :underfunded, focus: @nov)) == ["⛽ Tanken"]
    assert names(rows(months, filter: :snoozed)) == ["🏠 Miete"]
    assert [%{group: @daily}] = rows(months, filter: :overspent).groups
    assert length(rows(months, filter: :all).groups) == 3
  end

  test "counts the overspent, underfunded and snoozed categories of the focus month, whatever the filter" do
    months = [
      month(
        @oct,
        %{
          1 => %{available: -1},
          2 => %{underfunded: 5},
          3 => %{available: -9},
          4 => %{underfunded: 7, snoozed: true}
        },
        %{available: -2}
      )
    ]

    assert rows(months, filter: :snoozed).counts == %{overspent: 3, underfunded: 1, snoozed: 1}
  end

  test "has the uncategorised row while a shown month has activity or money in it" do
    assert rows([month(@oct, %{}), month(@nov, %{})]).uncategorised == nil

    assert %{cells: %{@nov => %CategoryMonth{available: -999}}} =
             rows([month(@oct, %{}), month(@nov, %{}, %{activity: -999, available: -999})]).uncategorised

    assert rows([month(@oct, %{}, %{available: 50})], filter: :overspent).uncategorised == nil
  end

  test "lists the income of the shown months per payee by name, the one without a payee last, unfiltered only" do
    income = %{
      {"Zinsen", @oct} => 12,
      {nil, @nov} => 5,
      {"Arbeitgeber", @oct} => 300_000,
      {"Alt", ~D[2026-09-01]} => 1
    }

    assert rows([month(@oct, %{}), month(@nov, %{})], income: income).income == [
             %{payee: "Arbeitgeber", amounts: %{@oct => 300_000}},
             %{payee: "Zinsen", amounts: %{@oct => 12}},
             %{payee: nil, amounts: %{@nov => 5}}
           ]

    assert rows([month(@oct, %{})], income: income, filter: :available).income == []
  end
end
