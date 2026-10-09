defmodule Abakus.BudgetFixturesTest do
  @moduledoc """
  Fictional budgets with hand-computed numbers in YNAB's month format (milliunits): `to_be_budgeted`, and per
  category `budgeted`, `activity`, `balance` and `goal_under_funded`. The check against YNAB's own numbers is the
  YNAB import's.
  """

  use ExUnit.Case, async: true

  alias Abakus.Budget

  @dir Path.expand("../fixtures/budget", __DIR__)

  for path <- Path.wildcard(Path.join(@dir, "*.json")) do
    @external_resource path

    test "reproduces YNAB's numbers: #{Path.basename(path, ".json")}" do
      fixture = unquote(path) |> File.read!() |> JSON.decode!()
      current = Date.from_iso8601!(fixture["current_month"])
      months = Map.new(Budget.months(budget(fixture), current), &{Date.to_iso8601(&1.month), &1})

      for expected <- fixture["months"] do
        month = Map.fetch!(months, expected["month"])

        assert milliunits(month.income) == expected["income"], expected["month"]
        assert milliunits(month.ready_to_assign) == expected["to_be_budgeted"], expected["month"]

        for category <- expected["categories"] do
          assert ynab(row(month, category["id"])) == category,
                 "#{expected["month"]} #{category["id"]}"
        end
      end
    end
  end

  defp budget(fixture) do
    {income, activity} =
      fixture["transactions"]
      |> Enum.group_by(&{&1["category_id"], month(&1["date"])}, &cents(&1["amount"]))
      |> Enum.map(fn {key, amounts} -> {key, Enum.sum(amounts)} end)
      |> Enum.split_with(fn {{id, _month}, _amount} -> id == "ready_to_assign" end)

    %Budget{
      categories: Enum.map(fixture["categories"], &%{id: &1["id"], hidden: &1["hidden"]}),
      income: Map.new(income, fn {{_id, month}, amount} -> {month, amount} end),
      activity: Map.new(activity),
      assigned:
        Map.new(
          fixture["assigned"],
          &{{&1["category_id"], month(&1["month"])}, cents(&1["amount"])}
        ),
      targets: Enum.group_by(fixture["targets"], & &1["category_id"], &target/1),
      snoozes: MapSet.new(fixture["snoozes"], &{&1["category_id"], month(&1["month"])})
    }
  end

  defp target(attrs) do
    %{
      from_month: month(attrs["from_month"]),
      cadence: String.to_existing_atom(attrs["cadence"]),
      amount: cents(attrs["amount"]),
      due_on: attrs["due_on"] && Date.from_iso8601!(attrs["due_on"]),
      set_aside: attrs["set_aside"]
    }
  end

  defp row(month, "uncategorised"), do: month.uncategorised
  defp row(month, id), do: Enum.find(month.categories, &(&1.category_id == id))

  defp ynab(row) do
    %{
      "id" => row.category_id || "uncategorised",
      "budgeted" => milliunits(row.assigned),
      "activity" => milliunits(row.activity),
      "balance" => milliunits(row.available),
      "goal_under_funded" => row.target && milliunits(row.underfunded)
    }
  end

  defp month(date), do: date |> Date.from_iso8601!() |> Date.beginning_of_month()

  defp cents(milliunits) when rem(milliunits, 10) == 0, do: div(milliunits, 10)
  defp milliunits(cents), do: cents * 10
end
