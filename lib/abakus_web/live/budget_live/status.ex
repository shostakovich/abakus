defmodule AbakusWeb.BudgetLive.Status do
  @moduledoc """
  What the budget shows about a category or month, as in YNAB: the available pill in the focus month and the quiet
  numbers of the others, the target's status in the category dialog, and Zu verteilen with Actual's short
  calculation and the later months it does not cover. A snoozed target counts as done. Colours are tones
  (`:error`, `:warning`, `:success`, `:neutral`, `:muted`); the components map them to theme tokens.
  """

  import AbakusWeb.Format

  alias Abakus.Budget.{CategoryMonth, Month}

  @doc """
  The available pill: `%{tone, icon, label}` (`label` names the state for screen readers), or `:zero`.
  """
  def pill(%CategoryMonth{available: available}) when available < 0,
    do: %{tone: :error, icon: nil, label: "überzogen"}

  def pill(%CategoryMonth{} = row) do
    cond do
      underfunded?(row) ->
        %{tone: :warning, icon: "circle-dashed", label: "unterfinanziert"}

      row.available > 0 and row.target != nil and not row.snoozed ->
        %{tone: :success, icon: "circle-check", label: "Ziel erreicht"}

      row.available > 0 ->
        %{tone: :success, icon: nil, label: nil}

      true ->
        :zero
    end
  end

  @doc "Available outside the focus month: its tone, with a dot while underfunded up to now or once assigned."
  def quiet(%CategoryMonth{} = row, current) do
    %{
      tone:
        cond do
          row.available < 0 -> :error
          row.available == 0 -> :muted
          true -> nil
        end,
      dot: underfunded?(row) and (not Date.after?(row.month, current) or row.assigned > 0)
    }
  end

  @doc "What the row's target still asks this month; nothing while it is snoozed."
  def open_need(%CategoryMonth{snoozed: true}), do: 0
  def open_need(%CategoryMonth{} = row), do: row.underfunded

  defp underfunded?(row), do: open_need(row) > 0

  @doc """
  A target's state as YNAB words it (overspent, paused, underfunded, funded): `%{title, tone}`, nil without a
  target.
  """
  def target_status(%CategoryMonth{target: nil}), do: nil

  def target_status(%CategoryMonth{available: available}) when available < 0,
    do: %{title: "Überzogen #{euros(-available)}", tone: :error}

  def target_status(%CategoryMonth{} = row) do
    spent = -row.activity
    budgeted = row.carried + row.assigned
    funded = if row.target.cadence == :by_date, do: "Im Plan", else: "Finanziert"

    cond do
      row.snoozed ->
        %{title: "Pausiert", tone: :neutral}

      row.underfunded > 0 ->
        %{title: "Noch #{euros(row.underfunded)} nötig", tone: :warning}

      spent > 0 ->
        %{title: "#{funded}, #{euros(spent)} von #{euros(budgeted)} ausgegeben", tone: :success}

      true ->
        %{title: funded, tone: :success}
    end
  end

  @doc """
  What a target asks for, as YNAB's target card says it: `{head, sub}`. A monthly target has no day; a repeating
  target by a date names its day without the year.
  """
  def target_head(%{cadence: :monthly, amount: amount, set_aside: true}),
    do: {"Jeden Monat weitere #{euros(amount)} zurücklegen", nil}

  def target_head(%{cadence: :monthly, amount: amount, set_aside: false}),
    do: {"Jeden Monat auffüllen bis #{euros(amount)}", nil}

  def target_head(%{cadence: :by_date} = target) do
    due = if target.repeats_yearly, do: day_month(target.due_on), else: long_date(target.due_on)
    every = if target.repeats_yearly, do: "Jedes Jahr", else: "Einmalig"
    mode = if target.set_aside, do: "weitere zurücklegen", else: "auffüllen bis"

    {"#{euros(target.amount)} bis #{due} ansparen",
     "#{every} · #{mode}, verteilt auf die Monate bis dahin"}
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

  @doc "Zu verteilen's tone and label."
  def ready(%Month{ready_to_assign_shown: shown}) when shown < 0,
    do: {:error, "Zu viel verteilt"}

  def ready(%Month{closed: true}), do: {:muted, "Nicht verteilt am Monatsende"}

  def ready(%Month{ready_to_assign_shown: shown}) when shown > 0,
    do: {:success, "Zu verteilen"}

  def ready(%Month{}), do: {nil, "Alles verteilt"}

  @doc """
  How Zu verteilen adds up, as in Actual: the funds (what last month left plus this month's income), last month's
  overspending, what is assigned and, in an open month, what later months have. Values are signed cents.
  """
  def calculation(%Month{} = month) do
    funds = month.not_assigned_last_month + month.income
    last = month_short(Date.shift(month.month, month: -1))

    [
      %{label: "Verfügbare Mittel", value: funds, tone: error(funds < 0)},
      %{
        label: "Überzogen im #{last}",
        value: -month.overspent_last_month,
        tone: error(month.overspent_last_month > 0)
      },
      %{label: "Zugewiesen", value: -month.assigned, tone: nil},
      not month.closed &&
        %{label: "Für spätere Monate", value: -month.assigned_in_future, tone: nil}
    ]
    |> Enum.filter(& &1)
  end

  defp error(true), do: :error
  defp error(false), do: nil

  @doc "The later months whose Zu verteilen is below zero, with the shortfall."
  def uncovered(%Month{month: month, uncovered: uncovered}) do
    for {later, shortfall} <- uncovered do
      name = if later.year == month.year, do: month_name(later), else: month_year(later)
      "#{name} nicht gedeckt: es fehlen #{euros(shortfall)}"
    end
  end
end
