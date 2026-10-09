defmodule Abakus.Budget do
  @moduledoc """
  The budget math, as in today's YNAB; pure, computed from the data in the struct, months are not stored.

  - Available = last month's available if positive + assigned + activity. An overspent category starts the next
    month at zero and the overspending comes off that month's Ready to Assign; a negative available is never
    carried (YNAB 4 could).
  - Ready to Assign per month, cumulative as YNAB's `to_be_budgeted`: income up to the month − assigned up to the
    month − overspending of the months before. A month shows it less what later months have assigned; a closed
    month (before the current one) shows it as it ended.
  - Assignments are never refused, so Ready to Assign can go below zero; a month lists the later months whose
    Ready to Assign is below zero (`uncovered`), up to the last month with data or that changes it.

  The struct holds `categories` (`%{id, hidden}` in budget order, hidden ones and hidden groups' included),
  `income` per month, `activity` and `assigned` per `{category_id, month}` (`nil` is the uncategorised row),
  `targets` (each category's target versions) and `snoozes` (`{category_id, month}`). Months are their first day;
  amounts are cents.
  """

  alias Abakus.Budget.{CategoryMonth, Month, Target}

  defstruct categories: [],
            income: %{},
            activity: %{},
            assigned: %{},
            targets: %{},
            snoozes: MapSet.new()

  @doc """
  Every month from the first with data to the month after the last with data, so the last month's overspending
  shows where it lands, widened to take in `current` and `through`. `current` decides which months are closed;
  `through` defaults to it. Any day stands for its month.
  """
  def months(%__MODULE__{} = budget, current, through \\ nil) do
    current = Date.beginning_of_month(current)
    data = data_months(budget)
    range = range(data, [current, Date.beginning_of_month(through || current)])

    rows =
      Enum.map([nil | Enum.map(budget.categories, & &1.id)], &category_months(budget, &1, range))

    [range | rows]
    |> Enum.zip_with(fn [month, uncategorised | categories] ->
      Month.new(month, Map.get(budget.income, month, 0), uncategorised, categories)
    end)
    |> chain_ready_to_assign()
    |> look_ahead(current, Enum.max([hd(range) | data], Date))
  end

  @doc """
  The assignments that fill the month's underfunded categories in budget order, as far as the month's Ready to
  Assign reaches without taking what later months have assigned (also in a closed month), the last one partly;
  hidden categories are skipped. Returns `{category_id, new_assigned}`.
  """
  def fill_underfunded(%__MODULE__{} = budget, month, current) do
    month = Date.beginning_of_month(month)
    %Month{} = shown = budget |> months(current, month) |> Enum.find(&(&1.month == month))
    hidden = for %{id: id, hidden: true} <- budget.categories, into: MapSet.new(), do: id
    rows = Enum.reject(shown.categories, &MapSet.member?(hidden, &1.category_id))
    free = max(shown.ready_to_assign - shown.assigned_in_future, 0)

    {fills, _left} = Enum.flat_map_reduce(rows, free, &fill/2)
    fills
  end

  defp fill(row, left) do
    case min(row.underfunded, left) do
      0 -> {[], left}
      amount -> {[{row.category_id, row.assigned + amount}], left - amount}
    end
  end

  defp data_months(budget) do
    Map.keys(budget.income) ++
      Enum.map(Map.keys(budget.activity), &elem(&1, 1)) ++
      Enum.map(Map.keys(budget.assigned), &elem(&1, 1))
  end

  defp range(data, asked) do
    first = Enum.min(asked ++ data, Date)
    last = Enum.max(asked ++ Enum.map(data, &Date.shift(&1, month: 1)), Date)

    first
    |> Stream.iterate(&Date.shift(&1, month: 1))
    |> Enum.take_while(&(Date.compare(&1, last) != :gt))
  end

  defp category_months(budget, category_id, range) do
    versions = Map.get(budget.targets, category_id, [])

    {rows, _available} =
      Enum.map_reduce(range, 0, fn month, last_available ->
        row =
          CategoryMonth.new(
            category_id,
            month,
            max(last_available, 0),
            Map.get(budget.assigned, {category_id, month}, 0),
            Map.get(budget.activity, {category_id, month}, 0)
          )

        target = Target.in_effect(versions, month)
        snoozed = MapSet.member?(budget.snoozes, {category_id, month})
        row = Target.apply(row, target, snoozed, &Map.get(budget.assigned, {category_id, &1}, 0))
        {row, row.available}
      end)

    rows
  end

  defp chain_ready_to_assign(months) do
    {months, _last} =
      Enum.map_reduce(months, {0, 0}, fn month, {ready_to_assign, overspent} ->
        month = Month.chain(month, ready_to_assign, overspent)
        {month, {month.ready_to_assign, month.overspent}}
      end)

    months
  end

  # Walks back from the last month: what later months have assigned, and which of them are short.
  defp look_ahead(months, current, last_data) do
    horizon = Enum.max([last_data, last_change(months)], Date)

    {months, _acc} =
      months
      |> Enum.reverse()
      |> Enum.map_reduce({0, []}, fn month, {assigned_later, uncovered} ->
        shown = Month.look_ahead(month, current, assigned_later, uncovered)

        uncovered =
          if short?(month, horizon),
            do: [{month.month, -month.ready_to_assign} | uncovered],
            else: uncovered

        {shown, {assigned_later + month.assigned, uncovered}}
      end)

    Enum.reverse(months)
  end

  defp short?(%Month{month: month, ready_to_assign: ready_to_assign}, horizon),
    do: ready_to_assign < 0 and Date.compare(month, horizon) != :gt

  # The last month whose Ready to Assign differs from the month before; the ones after only repeat it.
  defp last_change(months) do
    changed =
      for {month, last} <- Enum.zip(months, [0 | Enum.map(months, & &1.ready_to_assign)]),
          month.ready_to_assign != last,
          do: month.month

    List.last(changed, hd(months).month)
  end
end
