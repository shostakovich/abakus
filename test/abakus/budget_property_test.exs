defmodule Abakus.BudgetPropertyTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Abakus.Budget

  @first ~D[2026-01-01]
  @ids [1, 2, 3]

  defp month(i), do: Date.shift(@first, month: i)

  defp amounts(keys, range) do
    keys
    |> Enum.map(&{&1, one_of([constant(0), integer(range)])})
    |> fixed_map()
    |> map(fn amounts -> amounts |> Enum.reject(&(elem(&1, 1) == 0)) |> Map.new() end)
  end

  defp target do
    gen all(
          cadence <- member_of([:monthly, :yearly]),
          amount <- integer(1..50_000),
          set_aside <- boolean(),
          from <- integer(0..5),
          due <- integer(0..30)
        ) do
      %{
        from_month: month(from),
        cadence: cadence,
        amount: amount,
        set_aside: set_aside,
        due_on: if(cadence == :yearly, do: Date.shift(month(from + due), day: 14))
      }
    end
  end

  defp budget do
    gen all(
          count <- integer(1..6),
          months = Enum.map(0..(count - 1), &month/1),
          hidden <- list_of(boolean(), length: length(@ids)),
          income <- amounts(months, 0..200_000),
          assigned <- amounts(for(id <- @ids, m <- months, do: {id, m}), -20_000..60_000),
          activity <- amounts(for(id <- [nil | @ids], m <- months, do: {id, m}), -80_000..10_000),
          targets <- fixed_map(Map.new(@ids, &{&1, list_of(target(), max_length: 2)})),
          snoozes <- list_of(tuple({member_of(@ids), member_of(months)}), max_length: 3),
          current <- member_of(months)
        ) do
      budget = %Budget{
        categories: Enum.zip_with(@ids, hidden, &%{id: &1, hidden: &2}),
        income: income,
        assigned: assigned,
        activity: activity,
        targets: targets,
        snoozes: MapSet.new(snoozes)
      }

      {budget, current}
    end
  end

  defp row(month, nil), do: month.uncategorised
  defp row(month, id), do: Enum.find(month.categories, &(&1.category_id == id))

  defp up_to(map, month, key_month),
    do:
      map
      |> Enum.filter(&(Date.compare(key_month.(&1), month) != :gt))
      |> Enum.map(&elem(&1, 1))
      |> Enum.sum()

  property "the budget accounts hold Ready to Assign plus what is available" do
    check all({budget, current} <- budget()) do
      for month <- Budget.months(budget, current) do
        cash =
          up_to(budget.income, month.month, &elem(&1, 0)) +
            up_to(budget.activity, month.month, &elem(elem(&1, 0), 1))

        assert cash == month.ready_to_assign + month.available
      end
    end
  end

  property "available is last month's if positive plus assigned plus activity" do
    check all({budget, current} <- budget()) do
      months = Budget.months(budget, current)

      for id <- [nil | @ids] do
        rows = Enum.map(months, &row(&1, id))
        assert hd(rows).carried == 0

        for [last, row] <- Enum.chunk_every(rows, 2, 1, :discard) do
          assert row.carried == max(last.available, 0)
          assert row.available == row.carried + row.assigned + row.activity
        end
      end
    end
  end

  property "a month shows Ready to Assign less later assignments, or as it ended when closed" do
    check all({budget, current} <- budget()) do
      months = Budget.months(budget, current)

      for {month, i} <- Enum.with_index(months) do
        later = months |> Enum.drop(i + 1) |> Enum.map(& &1.assigned) |> Enum.sum()
        assert month.assigned_in_future == later

        expected = if month.closed, do: month.ready_to_assign, else: month.ready_to_assign - later
        assert month.ready_to_assign_shown == expected
        assert month.closed == Date.before?(month.month, current)
      end
    end
  end

  property "a month lists exactly the later months that are short, up to the last with data or change" do
    check all({budget, current} <- budget()) do
      months = Budget.months(budget, current)
      horizon = Enum.max([last_data(budget, months), last_change(months)], Date)

      for {month, i} <- Enum.with_index(months) do
        expected =
          for later <- Enum.drop(months, i + 1),
              later.ready_to_assign < 0 and Date.compare(later.month, horizon) != :gt,
              do: {later.month, -later.ready_to_assign}

        assert month.uncovered == expected
      end
    end
  end

  defp last_data(budget, months) do
    Enum.max(
      [hd(months).month | Map.keys(budget.income)] ++
        Enum.map(Map.keys(budget.activity) ++ Map.keys(budget.assigned), &elem(&1, 1)),
      Date
    )
  end

  defp last_change(months) do
    months
    |> Enum.zip([0 | Enum.map(months, & &1.ready_to_assign)])
    |> Enum.filter(fn {month, last} -> month.ready_to_assign != last end)
    |> Enum.map(fn {month, _last} -> month.month end)
    |> List.last(hd(months).month)
  end

  property "filling underfunded fills in budget order without taking what later months have" do
    check all(
            {budget, current} <- budget(),
            month <- member_of(Enum.map(Budget.months(budget, current), & &1.month))
          ) do
      before = budget |> Budget.months(current, month) |> Enum.find(&(&1.month == month))
      free = before.ready_to_assign - before.assigned_in_future
      fills = Budget.fill_underfunded(budget, month, current)
      hidden = for %{id: id, hidden: true} <- budget.categories, do: id

      {expected, _left} =
        before.categories
        |> Enum.reject(&(&1.category_id in hidden))
        |> Enum.flat_map_reduce(max(free, 0), fn row, left ->
          case min(row.underfunded, left) do
            0 -> {[], left}
            amount -> {[{row.category_id, row.assigned + amount}], left - amount}
          end
        end)

      assert fills == expected
    end
  end
end
