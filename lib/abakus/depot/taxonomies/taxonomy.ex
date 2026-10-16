defmodule Abakus.Depot.Taxonomies.Taxonomy do
  @moduledoc "A user's tree of classifications, such as regions or asset allocation."
  use Abakus.Schema

  schema "depot_taxonomies" do
    belongs_to :user, Abakus.Users.User
    field :name, :string
    field :source, :string
    field :dimensions, {:array, :string}, default: []
    field :pp_id, :string

    has_many :classifications, Abakus.Depot.Taxonomies.Classification

    timestamps()
  end
end
