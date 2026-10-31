defmodule Abakus.Kasse.BudgetLink.CategoryMapping do
  @moduledoc "The budget category the linked transactions of a Kasse category are booked in."

  use Abakus.Schema

  alias Abakus.Categories.Category, as: BudgetCategory
  alias Abakus.Kasse.Categories.Category

  @primary_key false
  schema "kasse_budget_category_mappings" do
    belongs_to :category, Category, primary_key: true
    belongs_to :budget_category, BudgetCategory, type: Ecto.UUID
  end
end
