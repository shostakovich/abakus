defmodule Abakus.Successors do
  @moduledoc """
  Where deleted rows with a successor, categories and merged payees, count (`sync/PROTOCOL.md`): for their successor,
  or that one's while it is deleted too. A chain that comes back to a row ends at the smallest id of its cycle.
  """

  import Abakus.Owned
  import Ecto.Query

  alias Abakus.Repo

  @doc "Each deleted row of the scope's user, by id, with the row it counts for."
  def of(scope, schema) do
    deleted =
      Map.new(
        Repo.all(
          from r in owned(schema, scope),
            where: not is_nil(r.deleted_at),
            select: {r.id, r.successor_id}
        )
      )

    Map.new(deleted, fn {id, _successor} -> {id, resolve(deleted, id, [])} end)
  end

  defp resolve(deleted, id, seen) do
    cond do
      id in seen -> seen |> Enum.take_while(&(&1 != id)) |> then(&Enum.min([id | &1]))
      Map.has_key?(deleted, id) and deleted[id] -> resolve(deleted, deleted[id], [id | seen])
      true -> id
    end
  end
end
