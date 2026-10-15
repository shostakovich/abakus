defmodule Abakus.Kasse.Activities.Activity do
  @moduledoc """
  An entry of the activity log: who did what, when. No actor means it happened automatically.
  The details hold the expense's title and amount, the changed fields of an update, or a text;
  all German as shown.
  """

  use Abakus.Schema

  alias Abakus.Kasse.Activities.Details
  alias Abakus.Kasse.Expenses.Expense
  alias Abakus.Kasse.Participants.Participant

  @actions [
    :expense_created,
    :expense_updated,
    :expense_deleted,
    :settings_updated,
    :recurring_created,
    :recurring_deleted
  ]

  schema "kasse_activities" do
    belongs_to :actor, Participant
    field :action, Ecto.Enum, values: @actions
    belongs_to :expense, Expense
    field :details, Details, default: %Details{}

    timestamps(updated_at: false)
  end
end
