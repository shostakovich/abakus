defmodule Abakus.Sync.Snapshot do
  @moduledoc """
  Everything a newly signed-in device starts from (`sync/PROTOCOL.md`): every synced row of the user, tombstones
  included, with its synced fields and their clocks, and the cursor the device reads after. One read transaction,
  so rows, clocks and cursor agree. Ready to Assign and its group are created first if the budget lacks them, so
  every device has the server's.
  """

  import Ecto.Query

  alias Abakus.{Categories, Repo, Sync}
  alias Abakus.Sync.{FieldClock, Tables}
  alias Abakus.Users.Scope

  @doc "`%{cursor: cursor, tables: %{table => [%{id, fields, clocks}]}}`; a field without a clock has none."
  def take(%Scope{user: %{id: user_id}} = scope) do
    Categories.ready_to_assign!(scope)

    {:ok, snapshot} =
      Repo.transact(
        fn ->
          cursor = Sync.cursor(scope)
          {:ok, %{cursor: cursor, tables: Map.new(Tables.schemas(), &table(&1, user_id))}}
        end,
        mode: :deferred
      )

    snapshot
  end

  defp table(schema, user_id) do
    table = Tables.table(schema)
    rows = Repo.all(rows_query(schema, user_id))
    clocks = clocks(table, Enum.map(rows, & &1.id))

    {table,
     Enum.map(rows, fn row ->
       %{
         id: row.id,
         fields:
           Map.new(Tables.values(row), fn {column, value} -> {to_string(column), value} end),
         clocks: Map.get(clocks, row.id, %{})
       }
     end)}
  end

  defp rows_query(schema, user_id) do
    case Tables.parent(schema) do
      nil ->
        from r in schema, where: r.user_id == ^user_id, order_by: r.id

      {parent, key} ->
        from r in schema,
          join: p in ^parent,
          on: p.id == field(r, ^key),
          where: p.user_id == ^user_id,
          order_by: r.id
    end
  end

  defp clocks(table, ids) do
    ids
    |> Enum.chunk_every(1000)
    |> Enum.flat_map(fn ids ->
      Repo.all(
        from f in FieldClock,
          where: f.table == ^table and f.row_id in ^ids,
          select: {f.row_id, f.column, f.clock}
      )
    end)
    |> Enum.group_by(&elem(&1, 0), fn {_id, column, clock} -> {column, clock} end)
    |> Map.new(fn {id, clocks} -> {id, Map.new(clocks)} end)
  end
end
