defmodule Abakus.Budget.Target do
  @moduledoc """
  What a "needed for spending" target asks for in a month (`needed`). Monthly: "set aside another" needs the
  amount, "refill up to" the amount less what is carried. By a date: what is missing is spread over the months up
  to the due month, rounded up to the cent; "set aside another" counts what was assigned since the cycle began,
  "refill up to" what is carried. After the due month one that repeats yearly starts its next cycle, the others
  ask nothing. A cycle begins the month after the last due month a version of the target reached, else with the
  target (its first version of the same cadence since it was last ended), so a changed amount keeps what was saved
  and a new date after a due month starts afresh. A snooze changes none of this, as in YNAB; the row only carries
  it.

  A surplus (more saved than the amount) is not spread: money taken out of it is underfunded only as far as it
  goes below the amount, as YNAB reports it.
  """

  alias Abakus.Budget.CategoryMonth

  @doc """
  The version in effect in the month (versions as `%{from_month, cadence, ...}`) with the month its current cycle
  began, as `{version, cycle_start}`; nil if there is none or it was ended.
  """
  def in_effect(versions, month) do
    versions
    |> Enum.filter(&(Date.compare(&1.from_month, month) != :gt))
    |> Enum.sort_by(& &1.from_month, {:desc, Date})
    |> case do
      [] -> nil
      [%{cadence: :none} | _] -> nil
      [version | earlier] -> {version, cycle_start(version, earlier, month)}
    end
  end

  defp cycle_start(%{cadence: :by_date} = version, earlier, month) do
    run = Enum.reverse([version | Enum.take_while(earlier, &(&1.cadence == :by_date))])
    due = due_month(version, month)
    ends = Enum.map(tl(run), & &1.from_month) ++ [due]

    run
    |> Enum.zip(ends)
    |> Enum.flat_map(fn {v, until} -> reached(v, until) end)
    |> Enum.filter(&Date.before?(&1, due))
    |> Enum.max(Date, fn -> nil end)
    |> case do
      nil -> hd(run).from_month
      last_due -> Date.shift(last_due, month: 1)
    end
  end

  defp cycle_start(version, _earlier, _month), do: version.from_month

  # The due months a version reached while it was in effect, up to (not including) `until`.
  defp reached(%{repeats_yearly: false} = version, until),
    do: Enum.filter([due_month(version, version.from_month)], &Date.before?(&1, until))

  defp reached(version, until) do
    version
    |> due_month(version.from_month)
    |> Stream.iterate(&Date.shift(&1, month: 12))
    |> Enum.take_while(&Date.before?(&1, until))
  end

  @doc """
  Fills in the row's target fields from `in_effect/2`; `assigned_in` gives the category's assignment in an
  earlier month.
  """
  def apply(%CategoryMonth{} = row, nil, _snoozed, _assigned_in), do: row

  def apply(%CategoryMonth{} = row, {target, cycle_start}, snoozed, assigned_in) do
    {asks, saved} = asks(target, cycle_start, row, assigned_in)
    {needed, underfunded} = need(asks, row.assigned)

    %{
      row
      | target: target,
        needed: needed,
        underfunded: underfunded,
        progress: progress(target, needed, underfunded, saved + row.assigned),
        snoozed: snoozed
    }
  end

  defp need(:nothing, _assigned), do: {0, 0}
  defp need(asks, assigned), do: {max(asks, 0), max(asks - assigned, 0)}

  # Returns what the month asks before its assignment, negative for a surplus or `:nothing` once a target by a
  # date is over, and, for a target by a date, what counts as saved before this month.
  defp asks(%{cadence: :monthly, amount: amount, set_aside: true}, _since, _row, _assigned_in),
    do: {amount, 0}

  defp asks(%{cadence: :monthly, amount: amount, set_aside: false}, _since, row, _assigned_in),
    do: {amount - row.carried, 0}

  defp asks(%{cadence: :by_date} = target, cycle_start, row, assigned_in) do
    due = due_month(target, row.month)
    saved = saved(target, cycle_start, row, assigned_in)
    {spread(target.amount - saved, months_between(row.month, due) + 1), saved}
  end

  defp spread(_missing, months) when months < 1, do: :nothing
  defp spread(missing, months) when missing > 0, do: ceil_div(missing, months)
  defp spread(surplus, _months), do: surplus

  defp saved(%{set_aside: false}, _cycle_start, row, _assigned_in), do: row.carried

  defp saved(%{set_aside: true}, cycle_start, row, assigned_in) do
    cycle_start
    |> Stream.iterate(&Date.shift(&1, month: 1))
    |> Enum.take_while(&Date.before?(&1, row.month))
    |> Enum.map(assigned_in)
    |> Enum.sum()
  end

  defp progress(%{cadence: :by_date, amount: amount}, _needed, _underfunded, saved),
    do: saved |> Kernel./(amount) |> max(0.0) |> min(1.0)

  defp progress(_monthly, _needed, 0, _saved), do: 1.0

  defp progress(_monthly, needed, underfunded, _saved),
    do: max(needed - underfunded, 0) / max(needed, underfunded)

  defp due_month(%{repeats_yearly: false, due_on: due_on}, _month),
    do: Date.beginning_of_month(due_on)

  defp due_month(%{repeats_yearly: true, due_on: due_on}, month) do
    due_on
    |> Date.beginning_of_month()
    |> Stream.iterate(&Date.shift(&1, month: 12))
    |> Enum.find(&(not Date.before?(&1, month)))
  end

  defp months_between(from, to), do: (to.year - from.year) * 12 + to.month - from.month

  defp ceil_div(amount, months), do: div(amount + months - 1, months)
end
