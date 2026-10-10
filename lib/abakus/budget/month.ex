defmodule Abakus.Budget.Month do
  @moduledoc """
  A month of the budget. `ready_to_assign` is cumulative, as YNAB's API reports it (`to_be_budgeted`);
  `ready_to_assign_shown` is what the month shows ("Zu verteilen"): Ready to Assign less `assigned_in_future`, or,
  in a closed month, as it ended. The month header explains it: `not_assigned_last_month` −
  `overspent_last_month` + `income` − `assigned` = `ready_to_assign`. `uncovered` lists later months whose Ready to
  Assign is below zero as `{month, shortfall}`. Totals include the uncategorised row; `overspent` is the sum of
  negative availables as a positive amount; `needed` and `underfunded` leave out snoozed categories.
  """

  alias Abakus.Budget.CategoryMonth

  defstruct [
    :month,
    categories: [],
    uncategorised: nil,
    closed: false,
    income: 0,
    carried: 0,
    assigned: 0,
    activity: 0,
    available: 0,
    overspent: 0,
    needed: 0,
    underfunded: 0,
    not_assigned_last_month: 0,
    overspent_last_month: 0,
    ready_to_assign: 0,
    assigned_in_future: 0,
    ready_to_assign_shown: 0,
    uncovered: []
  ]

  @doc "The month with its rows and their totals."
  def new(month, income, %CategoryMonth{} = uncategorised, categories) do
    rows = [uncategorised | categories]

    %__MODULE__{
      month: month,
      categories: categories,
      uncategorised: uncategorised,
      income: income,
      carried: sum(rows, & &1.carried),
      assigned: sum(rows, & &1.assigned),
      activity: sum(rows, & &1.activity),
      available: sum(rows, & &1.available),
      overspent: sum(rows, &max(-&1.available, 0)),
      needed: sum(rows, &if(&1.snoozed, do: 0, else: &1.needed)),
      underfunded: sum(rows, &if(&1.snoozed, do: 0, else: &1.underfunded))
    }
  end

  @doc "Ready to Assign from last month's and its overspending."
  def chain(%__MODULE__{} = month, not_assigned_last_month, overspent_last_month) do
    %{
      month
      | not_assigned_last_month: not_assigned_last_month,
        overspent_last_month: overspent_last_month,
        ready_to_assign:
          not_assigned_last_month - overspent_last_month + month.income - month.assigned
    }
  end

  @doc "What the month shows, given what later months have assigned and which of them are short."
  def look_ahead(%__MODULE__{} = month, current, assigned_in_future, uncovered) do
    closed = Date.before?(month.month, current)

    %{
      month
      | closed: closed,
        assigned_in_future: assigned_in_future,
        ready_to_assign_shown:
          if(closed, do: month.ready_to_assign, else: month.ready_to_assign - assigned_in_future),
        uncovered: uncovered
    }
  end

  defp sum(rows, fun), do: rows |> Enum.map(fun) |> Enum.sum()
end
