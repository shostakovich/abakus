defmodule Abakus.YnabImport.Targets do
  @moduledoc """
  Target versions and snoozes from the goal fields of YNAB's months. YNAB keeps no target history in the API:
  months before a target's creation month show it too, but ask nothing (`goal_under_funded` null), so a target
  starts in its creation month. From then on a change of the fields starts a new version; YNAB rolls a yearly
  target's due date forward, so a due date moved by whole years is no change. A month is snoozed when the goal's
  snooze date lies in it. Only "needed for spending" targets, monthly or yearly, get here (see `Unsupported`).
  """

  alias Abakus.YnabImport.Plan

  @doc "`{category_id, versions}` per regular category with targets; versions as `Categories.set_target/2` takes them."
  def versions(plan) do
    by_category = Enum.group_by(Plan.regular_category_months(plan), fn {_month, c} -> c["id"] end)

    for %{"id" => id} <- Plan.regular_categories(plan),
        versions = category_versions(Map.get(by_category, id, [])),
        versions != [],
        do: {id, versions}
  end

  @doc "`{category_id, month}` for each snoozed month."
  def snoozes(plan) do
    for {month, category} <- Plan.regular_category_months(plan),
        target(category, month),
        snoozed_in?(category, month),
        do: {category["id"], month}
  end

  defp category_versions(months) do
    {versions, _last} =
      Enum.flat_map_reduce(months, nil, fn {month, category}, last ->
        target = target(category, month)

        cond do
          same?(target, last) -> {[], last}
          is_nil(target) -> {[%{from_month: month, cadence: :none}], nil}
          true -> {[from(target, month)], target}
        end
      end)

    versions
  end

  defp target(%{"goal_type" => "NEED"} = category, month) do
    if created_by?(category, month), do: needed_for_spending(category)
  end

  defp target(_category, _month), do: nil

  defp created_by?(category, month) do
    case Plan.date(category["goal_creation_month"]) do
      nil -> true
      created -> not Date.before?(month, Date.beginning_of_month(created))
    end
  end

  defp needed_for_spending(category) do
    target = %{
      amount: Plan.cents(category["goal_target"]),
      set_aside: category["goal_needs_whole_amount"] != false
    }

    case {category["goal_cadence"], category["goal_cadence_frequency"]} do
      {1, 1} ->
        Map.merge(target, %{cadence: :monthly, due_on: nil})

      {13, 1} ->
        due_on = Plan.date(category["goal_target_date"] || category["goal_target_month"])
        Map.merge(target, %{cadence: :yearly, due_on: due_on})
    end
  end

  defp same?(nil, nil), do: true
  defp same?(nil, _last), do: false
  defp same?(_target, nil), do: false

  defp same?(target, last),
    do:
      Map.drop(target, [:due_on]) == Map.drop(last, [:due_on]) and
        same_day?(target.due_on, last.due_on)

  defp same_day?(nil, nil), do: true
  defp same_day?(%Date{} = a, %Date{} = b), do: {a.month, a.day} == {b.month, b.day}
  defp same_day?(_a, _b), do: false

  # The due date may not lie before the version starts; the year after is the same yearly target.
  defp from(%{due_on: %Date{} = due_on} = target, month) do
    due_on =
      due_on
      |> Stream.iterate(&Date.shift(&1, year: 1))
      |> Enum.find(&(not Date.before?(&1, month)))

    %{target | due_on: due_on} |> Map.put(:from_month, month)
  end

  defp from(target, month), do: Map.put(target, :from_month, month)

  defp snoozed_in?(category, month) do
    case Plan.date(category["goal_snoozed_at"]) do
      nil -> false
      snoozed -> Date.beginning_of_month(snoozed) == month
    end
  end
end
