defmodule Abakus.Positions do
  @moduledoc """
  Moving a row among its siblings, loaded in order of position and id: it goes before another or to the end, and
  the siblings are renumbered from 0, which also settles equal positions (`sync/PROTOCOL.md`, "Positions").
  """

  alias Abakus.Sync
  alias Ecto.Changeset

  @doc "Puts `row` before the row `before_id` of `others`, or at the end for nil."
  def insert_before(others, row, nil), do: {:ok, others ++ [row]}

  def insert_before(others, row, before_id) do
    case Enum.find_index(others, &(&1.id == before_id)) do
      nil -> {:error, :not_in_group}
      index -> {:ok, List.insert_at(others, index, row)}
    end
  end

  @doc """
  Numbers the rows from 0 in their order, setting `changes` on each too, as part of a `Sync.write/1`; writes only
  the rows that change. Returns the rows.
  """
  def renumber(rows, changes \\ []) do
    for {row, position} <- Enum.with_index(rows) do
      changeset = Changeset.change(row, Keyword.put(changes, :position, position))
      if changeset.changes == %{}, do: row, else: Sync.update!(changeset)
    end
  end
end
