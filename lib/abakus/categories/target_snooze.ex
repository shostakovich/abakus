defmodule Abakus.Categories.TargetSnooze do
  @moduledoc "A category's target is snoozed in this month: it counts as done then (see `Abakus.Budget.Month`)."

  use Abakus.Schema

  import Ecto.Changeset

  alias Abakus.Categories.Category

  schema "target_snoozes" do
    field :month, :date

    belongs_to :category, Category

    timestamps()
  end

  @doc "Changeset for a snooze whose `category_id` is set; any day stands for its month."
  def changeset(snooze, attrs) do
    snooze
    |> cast(attrs, [:month])
    |> update_change(:month, &Date.beginning_of_month/1)
    |> validate_required([:category_id, :month])
    |> unique_constraint([:category_id, :month])
  end
end
