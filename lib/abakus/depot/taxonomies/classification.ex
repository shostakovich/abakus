defmodule Abakus.Depot.Taxonomies.Classification do
  @moduledoc "A node of a taxonomy; `weight` is the target share of its parent in 1/100 percent."
  use Abakus.Schema

  schema "depot_classifications" do
    belongs_to :taxonomy, Abakus.Depot.Taxonomies.Taxonomy
    belongs_to :parent, __MODULE__
    field :name, :string
    field :note, :string
    field :color, :string
    field :weight, :integer
    field :rank, :integer, default: 0

    has_many :assignments, Abakus.Depot.Taxonomies.Assignment

    timestamps()
  end
end
