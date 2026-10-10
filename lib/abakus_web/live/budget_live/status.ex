defmodule AbakusWeb.BudgetLive.Status do
  @moduledoc """
  What the budget shows about a category or month, as in YNAB: the available pill in the focus month and the quiet
  numbers of the others, the target bar under the name with its status on hover, and
  Zu verteilen with Actual's short calculation and the later months it does not cover. A snoozed target counts as
  done.
  """

  import AbakusWeb.Format

  alias Abakus.Budget.{CategoryMonth, Month}

  @doc "The available pill's class and icon, or `:zero`."
  def pill(%CategoryMonth{available: available}) when available < 0, do: {"text-bg-danger", nil}

  def pill(%CategoryMonth{} = row) do
    cond do
      underfunded?(row) -> {"text-bg-warning", "half"}
      row.available > 0 -> {"text-bg-success", if(row.target && not row.snoozed, do: "okc")}
      true -> :zero
    end
  end

  @doc "Available outside the focus month: red, dimmed or plain, with a dot while underfunded up to now or once assigned."
  def quiet(%CategoryMonth{} = row, current) do
    %{
      class:
        cond do
          row.available < 0 -> "app-neg"
          row.available == 0 -> "app-zero"
          true -> nil
        end,
      dot: underfunded?(row) and (not Date.after?(row.month, current) or row.assigned > 0)
    }
  end

  defp underfunded?(%CategoryMonth{} = row), do: row.underfunded > 0 and not row.snoozed

  @doc """
  The target bar under the category name: its parts as `{percent, class}` and the status as its title (shown on
  hover, as the pill shows the amount already). Nil without a target, unless overspent.
  """
  def target_line(%CategoryMonth{available: available}) when available < 0,
    do: line("Überzogen #{euros(-available)}", [{100, "bg-danger"}])

  def target_line(%CategoryMonth{target: nil}), do: nil

  def target_line(%CategoryMonth{} = row) do
    spent = -row.activity
    budgeted = row.carried + row.assigned
    funded = if row.target.cadence == :yearly, do: "Im Plan", else: "Finanziert"

    cond do
      row.snoozed ->
        line("Pausiert", [{100, "bg-secondary"}])

      row.underfunded > 0 ->
        line("Noch #{euros(row.underfunded)} nötig", [{round(row.progress * 100), "bg-warning"}])

      spent > 0 and row.available == 0 ->
        line("Ausgegeben", [{100, "bg-success progress-bar-striped"}])

      spent > 0 ->
        part = round(spent * 100 / budgeted)

        line("#{funded}, #{euros(spent)} von #{euros(budgeted)} ausgegeben", [
          {part, "bg-success progress-bar-striped opacity-50"},
          {100 - part, "bg-success"}
        ])

      true ->
        line(funded, [{100, "bg-success"}])
    end
  end

  defp line(title, bars), do: %{title: title, bars: bars}

  @doc "Zu verteilen's class and label."
  def ready(%Month{ready_to_assign_shown: shown}) when shown < 0,
    do: {"text-danger", "Zu viel verteilt"}

  def ready(%Month{closed: true}), do: {"text-body-secondary", "Nicht verteilt am Monatsende"}

  def ready(%Month{ready_to_assign_shown: shown}) when shown > 0,
    do: {"text-success", "Zu verteilen"}

  def ready(%Month{}), do: {nil, "Alles verteilt ✓"}

  @doc """
  How Zu verteilen adds up, as in Actual: the funds (what last month left plus this month's income), last month's
  overspending, what is assigned and, in an open month, what later months have. Values are signed cents.
  """
  def calculation(%Month{} = month) do
    funds = month.not_assigned_last_month + month.income
    last = month_short(Date.shift(month.month, month: -1))

    [
      %{label: "Verfügbare Mittel", value: funds, class: red(funds < 0)},
      %{
        label: "Überzogen im #{last}",
        value: -month.overspent_last_month,
        class: red(month.overspent_last_month > 0)
      },
      %{label: "Zugewiesen", value: -month.assigned, class: nil},
      not month.closed &&
        %{label: "Für spätere Monate", value: -month.assigned_in_future, class: nil}
    ]
    |> Enum.filter(& &1)
  end

  defp red(true), do: "text-danger"
  defp red(false), do: nil

  @doc "The later months whose Zu verteilen is below zero, with the shortfall."
  def uncovered(%Month{month: month, uncovered: uncovered}) do
    for {later, shortfall} <- uncovered do
      name = if later.year == month.year, do: month_name(later), else: month_year(later)
      "#{name} nicht gedeckt: es fehlen #{euros(shortfall)}"
    end
  end
end
