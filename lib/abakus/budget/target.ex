defmodule Abakus.Budget.Target do
  @moduledoc """
  What a "needed for spending" target asks for in a month (`needed`). Monthly: "set aside another" needs the
  amount, "refill up to" the amount less what is carried. Yearly: what is missing is spread over the months up
  to the due month, rounded up to the cent, then the next cycle starts; "set aside another" counts what was
  assigned since the cycle began, "refill up to" what is carried. The first cycle begins with the target (its
  first version of the same cadence since it was last ended), later ones the month after the last due month. A
  snoozed target needs nothing.
  """

  alias Abakus.Budget.CategoryMonth

  @doc """
  The version in effect in the month (versions as `%{from_month, cadence, ...}`) with the month the target began,
  as `{version, since}`; nil if there is none or it was ended.
  """
  def in_effect(versions, month) do
    versions
    |> Enum.filter(&(Date.compare(&1.from_month, month) != :gt))
    |> Enum.sort_by(& &1.from_month, {:desc, Date})
    |> case do
      [] -> nil
      [%{cadence: :none} | _] -> nil
      [version | earlier] -> {version, since(version, earlier)}
    end
  end

  defp since(version, earlier) do
    earlier
    |> Enum.take_while(&(&1.cadence == version.cadence))
    |> List.last(version)
    |> Map.fetch!(:from_month)
  end

  @doc """
  Fills in the row's target fields from `in_effect/2`; `assigned_in` gives the category's assignment in an
  earlier month.
  """
  def apply(%CategoryMonth{} = row, nil, _snoozed, _assigned_in), do: row

  def apply(%CategoryMonth{} = row, {target, _since}, true, _assigned_in),
    do: %{row | target: target, snoozed: true}

  def apply(%CategoryMonth{} = row, {target, since}, false, assigned_in) do
    {needed, saved} = needed(target, since, row, assigned_in)
    underfunded = max(needed - row.assigned, 0)

    %{
      row
      | target: target,
        needed: needed,
        underfunded: underfunded,
        progress: progress(target, needed, underfunded, saved + row.assigned)
    }
  end

  # Returns what is needed and, for a yearly target, what counts as saved before this month.
  defp needed(%{cadence: :monthly, amount: amount, set_aside: true}, _since, _row, _assigned_in),
    do: {amount, 0}

  defp needed(%{cadence: :monthly, amount: amount, set_aside: false}, _since, row, _assigned_in),
    do: {max(amount - row.carried, 0), 0}

  defp needed(%{cadence: :yearly} = target, since, row, assigned_in) do
    due = due_month(target.due_on, row.month)
    saved = saved(target, cycle_start(target, since, due), row, assigned_in)
    {ceil_div(max(target.amount - saved, 0), months_between(row.month, due) + 1), saved}
  end

  defp cycle_start(target, since, due) do
    if due == due_month(target.due_on, since), do: since, else: Date.shift(due, month: -11)
  end

  defp saved(%{set_aside: false}, _cycle_start, row, _assigned_in), do: row.carried

  defp saved(%{set_aside: true}, cycle_start, row, assigned_in) do
    cycle_start
    |> Stream.iterate(&Date.shift(&1, month: 1))
    |> Enum.take_while(&Date.before?(&1, row.month))
    |> Enum.map(assigned_in)
    |> Enum.sum()
  end

  defp progress(%{cadence: :yearly, amount: amount}, _needed, _underfunded, saved),
    do: saved |> Kernel./(amount) |> max(0.0) |> min(1.0)

  defp progress(_monthly, 0, _underfunded, _saved), do: 1.0
  defp progress(_monthly, needed, underfunded, _saved), do: (needed - underfunded) / needed

  defp due_month(due_on, month) do
    due_on
    |> Date.beginning_of_month()
    |> Stream.iterate(&Date.shift(&1, month: 12))
    |> Enum.find(&(not Date.before?(&1, month)))
  end

  defp months_between(from, to), do: (to.year - from.year) * 12 + to.month - from.month

  defp ceil_div(amount, months), do: div(amount + months - 1, months)
end
