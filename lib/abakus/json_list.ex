defmodule Abakus.JsonList do
  @moduledoc """
  A query's test that a value is one of a list, the list passed as one JSON parameter: SQLite takes at most 32766
  variables, and a list can hold more.
  """

  @doc "In a query: whether `value` is one of `list`."
  defmacro in_json(value, list) do
    quote do
      fragment(
        "? IN (SELECT value FROM json_each(?))",
        unquote(value),
        ^JSON.encode!(unquote(list))
      )
    end
  end

  @doc "The ids of `records`."
  def ids(records), do: Enum.map(records, & &1.id)
end
