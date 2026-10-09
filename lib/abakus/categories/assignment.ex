defmodule Abakus.Categories.Assignment do
  @moduledoc "Money assigned to a category in a month; may be negative, as in YNAB."

  use Abakus.Schema

  import Ecto.Changeset

  alias Abakus.Amount
  alias Abakus.Categories.Category

  schema "assignments" do
    field :month, :date
    field :amount, :integer

    belongs_to :category, Category

    timestamps()
  end

  @doc "Changeset for an assignment whose `category_id` is set; any day stands for its month."
  def changeset(assignment, attrs) do
    assignment
    |> cast(attrs, [:month, :amount])
    |> update_change(:month, &Date.beginning_of_month/1)
    |> validate_required([:category_id, :month, :amount])
    |> Amount.validate()
    |> unique_constraint([:category_id, :month])
  end
end
