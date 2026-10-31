defmodule Abakus.Schema do
  @moduledoc false

  @doc """
  With `uuid: true` the schema has UUIDv7 ids and its references are UUIDs (ADR 0025); a reference to an integer
  id, such as the user's, then needs `type: :id`.
  """
  defmacro __using__(opts) do
    quote do
      use Ecto.Schema

      @timestamps_opts [type: :utc_datetime_usec]

      if unquote(Keyword.get(opts, :uuid, false)) do
        @primary_key {:id, Ecto.UUID, autogenerate: [version: 7, precision: :monotonic]}
        @foreign_key_type Ecto.UUID
      end
    end
  end

  @doc "A moment with the microsecond precision of `:utc_datetime_usec` fields."
  def usec(%DateTime{microsecond: {microsecond, _precision}} = moment),
    do: %{moment | microsecond: {microsecond, 6}}

  @max_id 9_223_372_036_854_775_807

  @doc """
  An id as a client sends it (text or integer), or `:error` when no row can have it: SQLite ids are positive
  64-bit integers, and a larger one fails the query instead of finding nothing.
  """
  def cast_id(id) do
    case Ecto.Type.cast(:id, id) do
      {:ok, id} when is_integer(id) and id in 1..@max_id//1 -> {:ok, id}
      _invalid -> :error
    end
  end
end
