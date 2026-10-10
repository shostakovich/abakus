defmodule Abakus.Budget.CategoryMonth do
  @moduledoc """
  A category in a month; `category_id` nil is the uncategorised row (transactions without a category).
  `carried` is last month's available if positive. `needed` is what the target asks for this month,
  `underfunded` what of it is not assigned yet, `progress` from 0 to 1 (nil without a target); `saved` is what counts
  toward a target by a date's amount (nil for other targets). A `snoozed` month
  still has them, but counts as done: the month's underfunded total and filling leave it out.
  """

  defstruct [
    :category_id,
    :month,
    :target,
    :progress,
    :saved,
    carried: 0,
    assigned: 0,
    activity: 0,
    available: 0,
    needed: 0,
    underfunded: 0,
    snoozed: false
  ]

  def new(category_id, month, carried, assigned, activity) do
    %__MODULE__{
      category_id: category_id,
      month: month,
      carried: carried,
      assigned: assigned,
      activity: activity,
      available: carried + assigned + activity
    }
  end
end
