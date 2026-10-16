defmodule Abakus.Depot.BudgetLink.Link do
  @moduledoc """
  The budget owner's Depot linked to the budget: purchases get `category`, and Depot transactions dated before
  `start_date` stay in the Depot only.
  """

  use Abakus.Schema

  import Ecto.Changeset

  @primary_key false
  schema "depot_budget_links" do
    belongs_to :user, Abakus.Users.User, primary_key: true
    belongs_to :category, Abakus.Categories.Category
    field :start_date, :date

    timestamps()
  end

  def changeset(link, attrs) do
    link
    |> cast(attrs, [:category_id, :start_date])
    |> validate_required([:category_id, :start_date])
  end
end
