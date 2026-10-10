defmodule Abakus.Schema do
  @moduledoc false

  defmacro __using__(_opts) do
    quote do
      use Ecto.Schema

      @timestamps_opts [type: :utc_datetime_usec]
    end
  end

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
