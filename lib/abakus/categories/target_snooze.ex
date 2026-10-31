defmodule Abakus.Categories.TargetSnooze do
  @moduledoc "A category's target is snoozed in this month: it counts as done then (see `Abakus.Budget.Month`)."

  use Abakus.Schema, uuid: true

  import Ecto.Changeset

  alias Abakus.Categories.Category
  alias Abakus.Ids

  schema "target_snoozes" do
    field :month, :date
    field :deleted_at, :utc_datetime_usec

    belongs_to :category, Category
    belongs_to :user, Abakus.Users.User, type: :id

    timestamps()
  end

  @doc "Changeset for a snooze whose `category_id` and `user_id` are set; any day stands for its month."
  def changeset(snooze, attrs) do
    snooze
    |> cast(attrs, [:month])
    |> update_change(:month, &Date.beginning_of_month/1)
    |> validate_required([:category_id, :user_id, :month])
    |> unique_constraint([:category_id, :month])
    |> Ids.put_named_id(:month, &Ids.target_snooze/2)
  end
end
