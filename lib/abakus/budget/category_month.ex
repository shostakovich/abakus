defmodule Abakus.Budget.CategoryMonth do
  @moduledoc """
  A category in a month; `category_id` nil is the uncategorised row (transactions without a category).
  `carried` is last month's available if positive. `needed` is what the target asks for this month,
  `underfunded` what of it is not assigned yet, `progress` from 0 to 1 (nil without a target or when snoozed).
  """

  defstruct [
    :category_id,
    :month,
    :target,
    :progress,
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
