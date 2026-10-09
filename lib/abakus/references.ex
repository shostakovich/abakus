defmodule Abakus.References do
  @moduledoc """
  Checks references before writing, so a missing row is a changeset error with Ecto's message ("does not exist",
  "existiert nicht" in the UI) instead of a constraint error. The foreign keys stay as the last line of defence.
  """

  import Ecto.Query

  alias Abakus.Repo
  alias Ecto.Changeset

  @doc "The ids among `ids` that have a row in `schema`, in one query."
  def existing(schema, ids) do
    case ids |> Enum.reject(&is_nil/1) |> Enum.uniq() do
      [] -> MapSet.new()
      ids -> MapSet.new(Repo.all(from r in schema, where: r.id in ^ids, select: r.id))
    end
  end

  @doc "Adds the error to `field` when its change is an id that is not in `existing`."
  def validate(changeset, field, existing) do
    case Changeset.get_change(changeset, field) do
      nil -> changeset
      id -> if MapSet.member?(existing, id), do: changeset, else: not_found(changeset, field)
    end
  end

  @doc "Checks one changed reference against `schema`."
  def validate_exists(changeset, field, schema) do
    validate(changeset, field, existing(schema, [Changeset.get_change(changeset, field)]))
  end

  def not_found(changeset, field),
    do: Changeset.add_error(changeset, field, "does not exist", validation: :assoc)
end
