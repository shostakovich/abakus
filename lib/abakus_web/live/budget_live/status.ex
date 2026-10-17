defmodule AbakusWeb.BudgetLive.Status do
  @moduledoc """
  What the budget shows about a category or month, as in YNAB: the available cell, the target in the category
  dialog, and Zu verteilen with YNAB 4's calculation and the later months it does not cover. A snoozed target counts
  as done. Colours are tones (`:error`, `:warning`, `:success`, `:muted`); the components map them to theme tokens.
  """

  import Abakus.Format,
    only: [long_date: 1, day_month: 1, month_name: 1, month_abbr: 1]

  alias Abakus.Budget.{CategoryMonth, Month}
  alias Abakus.Money

  @doc """
  The available cell: `%{tone, icon, label}`. The tone colours the number (red when overspent, amber while the
  target is underfunded, muted at zero), the icon marks the target as underfunded, funded or snoozed, and `label`
  names the state for screen readers. An underfunded target shows only in a month being budgeted (`budgeting?/2`).
  """
  def available(%CategoryMonth{available: available}, _budgeting) when available < 0,
    do: %{tone: :error, icon: nil, label: "überzogen"}

  def available(%CategoryMonth{} = row, budgeting) do
    tone = if row.available == 0, do: :muted

    cond do
      row.target != nil and row.snoozed ->
        %{tone: tone, icon: "pause", label: "Ziel pausiert"}

      underfunded?(row) ->
        underfunded(budgeting, tone)

      row.target != nil and row.available > 0 ->
        %{tone: nil, icon: "circle-check", label: "Ziel erreicht"}

      true ->
        %{tone: tone, icon: nil, label: nil}
    end
  end

  defp underfunded(true, _tone), do: %{tone: :warning, icon: "clock", label: "unterfinanziert"}
  defp underfunded(false, tone), do: %{tone: tone, icon: nil, label: nil}

  @doc "Whether the month is being budgeted: the current month, and any other with money assigned."
  def budgeting?(%Month{month: month, assigned: assigned}, current),
    do: month == current or assigned != 0

  @doc "What the row's target still asks this month; nothing while it is snoozed."
  def open_need(%CategoryMonth{snoozed: true}), do: 0
  def open_need(%CategoryMonth{} = row), do: row.underfunded

  defp underfunded?(row), do: open_need(row) > 0

  @doc """
  The target's state this month in one sentence, for the category dialog: `%{text, tone, icon}` (the icons of the
  available cell), nil without a target. Overspending wins over snoozing.
  """
  def target_status(%CategoryMonth{target: nil}), do: nil

  def target_status(%CategoryMonth{available: available}) when available < 0,
    do: %{text: "Überzogen um #{Money.euros(-available)}.", tone: :error, icon: nil}

  def target_status(%CategoryMonth{snoozed: true} = row),
    do: %{text: "Pausiert im #{month_name(row.month)}.", tone: :muted, icon: "pause"}

  def target_status(%CategoryMonth{underfunded: underfunded}) when underfunded > 0,
    do: %{text: "Noch #{Money.euros(underfunded)} diesen Monat.", tone: :warning, icon: "clock"}

  def target_status(%CategoryMonth{target: %{cadence: :by_date, amount: amount}, saved: saved})
      when is_integer(saved) and saved < amount,
      do: %{text: "Im Plan.", tone: :success, icon: "circle-check"}

  def target_status(%CategoryMonth{}),
    do: %{text: "Erfüllt.", tone: :success, icon: "circle-check"}

  @doc """
  What a target asks for, in one sentence. A repeating target by a date names its day without the year.
  """
  def target_head(%{cadence: :monthly, amount: amount, set_aside: true}),
    do: "Jeden Monat weitere #{Money.euros(amount)} zurücklegen"

  def target_head(%{cadence: :monthly, amount: amount, set_aside: false}),
    do: "Jeden Monat auffüllen bis #{Money.euros(amount)}"

  def target_head(%{cadence: :by_date} = target) do
    by =
      if target.repeats_yearly,
        do: "Jedes Jahr bis zum #{day_month(target.due_on)}",
        else: "Bis zum #{long_date(target.due_on)}"

    if target.set_aside,
      do: "#{by} weitere #{Money.euros(target.amount)} zurücklegen",
      else: "#{by} auf #{Money.euros(target.amount)} ansparen"
  end

  @doc """
  Where a target by a date should stand after this month, in percent of its amount, for the marker on its bar;
  nil for other targets.
  """
  def target_mark(%CategoryMonth{target: %{cadence: :by_date, amount: amount}} = row)
      when amount > 0 do
    min(100, round(((row.saved || 0) + open_need(row)) * 100 / amount))
  end

  def target_mark(%CategoryMonth{}), do: nil

  @doc "Zu verteilen's tone and label: an open month's by its sign, a past month's as it ended."
  def ready(%Month{closed: true, ready_to_assign_shown: shown}) when shown < 0,
    do: {:error, "Zu viel verteilt"}

  def ready(%Month{closed: true}), do: {:muted, "Nicht verteilt am Monatsende"}

  def ready(%Month{ready_to_assign_shown: shown}) when shown > 0, do: {:success, "Zu verteilen"}
  def ready(%Month{ready_to_assign_shown: shown}) when shown < 0, do: {:error, "Zu verteilen"}
  def ready(%Month{}), do: {nil, "Zu verteilen"}

  @doc """
  How Zu verteilen adds up, as YNAB 4's month header: what last month left unassigned and overspent, this month's
  income and assignments and, in an open month, what later months have assigned. Signed cents that add up to
  `ready_to_assign_shown`.
  """
  def calculation(%Month{} = month) do
    last = month_abbr(Date.shift(month.month, month: -1))
    this = month_abbr(month.month)
    later = if month.closed, do: 0, else: month.assigned_in_future

    [
      %{
        label: "Nicht verteilt im #{last}",
        value: month.not_assigned_last_month,
        tone: error(month.not_assigned_last_month < 0)
      },
      %{
        label: "Überzogen im #{last}",
        value: -month.overspent_last_month,
        tone: error(month.overspent_last_month > 0)
      },
      %{label: "Einnahmen im #{this}", value: month.income, tone: nil},
      %{label: "Zugewiesen im #{this}", value: -month.assigned, tone: nil},
      later != 0 && %{label: "Für spätere Monate", value: -later, tone: nil}
    ]
    |> Enum.filter(& &1)
  end

  defp error(true), do: :error
  defp error(false), do: nil

  @doc "The later months whose Zu verteilen is below zero, as lines of the calculation: the shortfall, negative."
  def uncovered(%Month{month: month, uncovered: uncovered}) do
    for {later, shortfall} <- uncovered do
      name =
        if later.year == month.year,
          do: month_abbr(later),
          else: "#{month_abbr(later)} #{later.year}"

      %{label: "Nicht gedeckt im #{name}", value: -shortfall, tone: :error}
    end
  end
end
