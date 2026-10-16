defmodule Abakus.Depot.Securities.AttributeType do
  @moduledoc "An attribute such as TER or provider, as defined in PP; values live in `attributes` maps."
  use Abakus.Schema

  schema "depot_attribute_types" do
    field :pp_id, :string
    field :name, :string
    field :column_label, :string
    field :target, :string
    field :value_type, :string
    field :converter, :string

    timestamps()
  end
end
