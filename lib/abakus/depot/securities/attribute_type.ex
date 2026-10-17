defmodule Abakus.Depot.Securities.AttributeType do
  @moduledoc "An attribute such as TER or provider; values live in `attributes` maps under its `key`."
  use Abakus.Schema

  schema "depot_attribute_types" do
    field :key, :string
    field :name, :string
    field :column_label, :string
    field :target, :string
    field :value_type, :string
    field :converter, :string

    timestamps()
  end
end
