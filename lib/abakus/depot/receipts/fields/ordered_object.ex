defmodule Abakus.Depot.Receipts.Fields.OrderedObject do
  @moduledoc """
  A JSON object whose keys keep their order, as `{key, value}` pairs: a model constrained by a
  schema answers its properties in the schema's order, and a map has none.
  """
  defstruct pairs: []

  defimpl JSON.Encoder do
    def encode(%{pairs: pairs}, encoder), do: :json.encode_key_value_list(pairs, encoder)
  end
end
