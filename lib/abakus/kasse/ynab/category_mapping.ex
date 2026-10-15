defmodule Abakus.Kasse.Ynab.CategoryMapping do
  @moduledoc "The YNAB category a person's shares of a category are booked to."

  use Abakus.Schema

  alias Abakus.Kasse.Categories.Category
  alias Abakus.Kasse.Participants.Participant

  @primary_key false
  schema "kasse_ynab_category_mappings" do
    belongs_to :participant, Participant, primary_key: true
    belongs_to :category, Category, primary_key: true
    field :ynab_category_id, :string
  end
end
