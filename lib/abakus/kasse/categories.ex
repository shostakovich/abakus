defmodule Abakus.Kasse.Categories do
  @moduledoc """
  The categories of expenses, in an order the group chooses. New ones go before "Sonstiges";
  positions are renumbered 10, 20, … whenever the order changes. Every change is logged. The functions take the
  caller's scope, which `Abakus.Kasse.Access` checks.
  """

  import Ecto.Query

  alias Abakus.Kasse.{Access, Activities}
  alias Abakus.Kasse.Categories.Category
  alias Abakus.Repo
  alias Abakus.Users.Scope
  alias Ecto.Changeset

  @other "sonstiges"

  @doc "The categories in their order: `:active` (default), `:archived` or `:all`."
  def list_categories(%Scope{} = scope, which \\ :active) do
    Access.check!(scope)
    all(which)
  end

  defp all(which) do
    Category
    |> archived(which)
    |> order_by([c], [c.position, fragment("? COLLATE NOCASE", c.name), c.id])
    |> Repo.all()
  end

  defp archived(query, :active), do: where(query, [c], is_nil(c.archived_at))
  defp archived(query, :archived), do: where(query, [c], not is_nil(c.archived_at))
  defp archived(query, :all), do: query

  @doc "The category with `id`, or nil."
  def get_category(%Scope{} = scope, id) do
    Access.check!(scope)
    Repo.get(Category, id)
  end

  @doc "The category with `id`; raises if there is none."
  def get_category!(%Scope{} = scope, id) do
    Access.check!(scope)
    Repo.get!(Category, id)
  end

  @doc "A changeset for the name form."
  def change_category(%Category{} = category, attrs \\ %{}),
    do: Category.changeset(category, attrs)

  @doc ~s(Adds a category before the active "Sonstiges", wherever that was moved to, or at the end.)
  def create_category(%Scope{} = scope, attrs) do
    actor_id = Access.actor_id!(scope)

    Repo.transact(fn ->
      active = all(:active)

      with {:ok, category} <- Repo.insert(Category.changeset(%Category{}, attrs)),
           :ok <- renumber(insert_before_other(active, category)),
           {:ok, _activity} <-
             Activities.log_settings(actor_id, "Kategorie „#{category.name}“ hinzugefügt") do
        {:ok, Repo.reload!(category)}
      end
    end)
  end

  defp insert_before_other(active, category) do
    index = Enum.find_index(active, &(String.downcase(&1.name) == @other)) || length(active)
    List.insert_at(active, index, category)
  end

  defp renumber(categories) do
    categories
    |> Enum.with_index(1)
    |> Enum.each(fn {category, index} ->
      Repo.update_all(where(Category, id: ^category.id), set: [position: index * 10])
    end)
  end

  @doc "Renames a category; logged only when the name changes."
  def rename_category(%Scope{} = scope, %Category{} = category, attrs) do
    actor_id = Access.actor_id!(scope)

    Repo.transact(fn ->
      with {:ok, renamed} <- Repo.update(Category.changeset(category, attrs)),
           {:ok, _activity} <- log_rename(actor_id, category.name, renamed.name) do
        {:ok, renamed}
      end
    end)
  end

  defp log_rename(_actor_id, same, same), do: {:ok, nil}

  defp log_rename(actor_id, old, new),
    do: Activities.log_settings(actor_id, "Kategorie „#{old}“ umbenannt in „#{new}“")

  @doc """
  Swaps a category with its neighbour `:up` or `:down`; at the edge nothing happens. Only active
  categories move: `{:error, :not_found}` otherwise.
  """
  def move_category(%Scope{} = scope, %Category{id: id}, direction)
      when direction in [:up, :down] do
    actor_id = Access.actor_id!(scope)

    Repo.transact(fn ->
      active = all(:active)

      case Enum.find_index(active, &(&1.id == id)) do
        nil -> {:error, :not_found}
        index -> move(actor_id, active, index, direction)
      end
    end)
  end

  defp move(actor_id, active, index, direction) do
    other = if direction == :up, do: index - 1, else: index + 1
    category = Enum.at(active, index)

    if other in 0..(length(active) - 1)//1 do
      active
      |> List.replace_at(index, Enum.at(active, other))
      |> List.replace_at(other, category)
      |> renumber()

      where = if direction == :up, do: "oben", else: "unten"

      with {:ok, _activity} <-
             Activities.log_settings(
               actor_id,
               "Kategorie „#{category.name}“ nach #{where} verschoben"
             ),
           do: {:ok, Repo.reload!(category)}
    else
      {:ok, category}
    end
  end

  @doc "Archives a category; old expenses keep it."
  def archive_category(%Scope{} = scope, %Category{} = category) do
    actor_id = Access.actor_id!(scope)
    Repo.transact(fn -> set_archived(actor_id, category, DateTime.utc_now(), "archiviert") end)
  end

  @doc "Brings an archived category back."
  def reactivate_category(%Scope{} = scope, %Category{} = category) do
    actor_id = Access.actor_id!(scope)
    Repo.transact(fn -> set_archived(actor_id, category, nil, "reaktiviert") end)
  end

  # Logged even when nothing changes.
  defp set_archived(actor_id, category, archived_at, verb) do
    with {:ok, category} <-
           category |> Changeset.change(archived_at: archived_at) |> Repo.update(),
         {:ok, _activity} <-
           Activities.log_settings(actor_id, "Kategorie „#{category.name}“ #{verb}") do
      {:ok, category}
    end
  end
end
