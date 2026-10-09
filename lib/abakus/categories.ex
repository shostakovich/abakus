defmodule Abakus.Categories do
  @moduledoc "Category groups and categories with their assignments and targets."

  import Ecto.Query

  alias Abakus.Categories.{
    Assignment,
    Category,
    CategoryGroup,
    TargetSnooze,
    TargetVersion
  }

  alias Abakus.{Names, References, Repo}
  alias Ecto.Changeset

  @doc "Groups with their categories in budget order, without the internal ones."
  def list_category_groups do
    categories = from c in Category, where: not c.internal, order_by: [c.position, c.id]

    Repo.all(
      from g in CategoryGroup,
        where: not g.internal,
        order_by: [g.position, g.id],
        preload: [categories: ^categories]
    )
  end

  @doc "The internal category income is assigned to (UI: \"Zu verteilen\")."
  def ready_to_assign! do
    Repo.one!(
      from c in Category, where: c.internal and c.name == ^Category.ready_to_assign_name()
    )
  end

  def create_category_group(attrs) do
    %CategoryGroup{}
    |> CategoryGroup.changeset(attrs)
    |> Repo.insert()
  end

  def update_category_group(%CategoryGroup{} = group, attrs) do
    group
    |> CategoryGroup.changeset(attrs)
    |> Repo.update()
  end

  def create_category(attrs) do
    %Category{}
    |> Category.changeset(attrs)
    |> validate_group()
    |> Repo.insert()
  end

  def update_category(%Category{} = category, attrs) do
    category
    |> Category.changeset(attrs)
    |> validate_group()
    |> Repo.update()
  end

  defp validate_group(changeset) do
    with {:ok, group_id} <- Changeset.fetch_change(changeset, :category_group_id),
         %CategoryGroup{internal: false} <- Repo.get(CategoryGroup, group_id) do
      changeset
    else
      :error ->
        changeset

      nil ->
        References.not_found(changeset, :category_group_id)

      %CategoryGroup{internal: true} ->
        Changeset.add_error(changeset, :category_group_id, "ist intern")
    end
  end

  @doc """
  Finds a category by name, ignoring emoji and case. Visible regular categories win over hidden ones with the same
  name; an internal category's name means it alone.
  """
  def find_category_by_name(name) when is_binary(name) do
    key = Names.lookup_key(name)

    candidates =
      Repo.all(
        from c in Category,
          join: g in assoc(c, :category_group),
          where: c.lookup_key == ^key,
          select: {c, g.hidden}
      )

    case for {%Category{internal: true} = category, _hidden} <- candidates, do: {category, true} do
      [] -> Enum.map(candidates, fn {c, group_hidden} -> {c, not (c.hidden or group_hidden)} end)
      internal -> internal
    end
    |> Names.pick()
  end

  @doc "Sets the amount assigned to a category in a month (any day of it)."
  def assign(%Category{} = category, month, amount) do
    %Assignment{category_id: category.id}
    |> Assignment.changeset(%{month: month, amount: amount})
    |> validate_regular(category)
    |> Repo.insert(
      on_conflict: {:replace, [:amount, :updated_at]},
      conflict_target: [:category_id, :month],
      returning: true
    )
  end

  @doc """
  Sets a category's target from a month on (attrs: `from_month`, any day of it, `cadence`, `amount`, `due_on`,
  `set_aside`); replaces a version that starts in the same month. Cadence `none` removes the target from that
  month on.
  """
  def set_target(%Category{} = category, attrs) do
    %TargetVersion{category_id: category.id}
    |> TargetVersion.changeset(attrs)
    |> validate_regular(category)
    |> Repo.insert(
      on_conflict: {:replace, [:cadence, :amount, :due_on, :set_aside, :updated_at]},
      conflict_target: [:category_id, :from_month],
      returning: true
    )
  end

  @doc "The target version in effect in a month (any day of it), or nil if the category has no target then."
  def target_for(%Category{id: category_id}, month) do
    month = month!(month)

    version =
      Repo.one(
        from v in TargetVersion,
          where: v.category_id == ^category_id and v.from_month <= ^month,
          order_by: [desc: v.from_month],
          limit: 1
      )

    case version do
      %TargetVersion{cadence: :none} -> nil
      version -> version
    end
  end

  @doc "Snoozes a category's target in a month (any day of it); snoozing it again returns the snooze there is."
  def snooze_target(%Category{} = category, month) do
    %TargetSnooze{category_id: category.id}
    |> TargetSnooze.changeset(%{month: month})
    |> validate_regular(category)
    |> Repo.insert(
      on_conflict: {:replace, [:month]},
      conflict_target: [:category_id, :month],
      returning: true
    )
  end

  def unsnooze_target(%Category{} = category, month) do
    Repo.delete_all(snoozes(category, month))
    :ok
  end

  def target_snoozed?(%Category{} = category, month), do: Repo.exists?(snoozes(category, month))

  defp snoozes(%Category{id: category_id}, month) do
    month = month!(month)
    from s in TargetSnooze, where: s.category_id == ^category_id and s.month == ^month
  end

  # A month given as any day of it, as a date or ISO 8601 string.
  defp month!(value) do
    case Ecto.Type.cast(:date, value) do
      {:ok, %Date{} = date} -> Date.beginning_of_month(date)
      _ -> raise ArgumentError, "not a date: #{inspect(value)}"
    end
  end

  # Looks the category up again, so a stale struct gives an error instead of a constraint error.
  defp validate_regular(changeset, %Category{id: id}) do
    case Repo.get(Category, id) do
      nil -> References.not_found(changeset, :category_id)
      %Category{internal: true} -> Changeset.add_error(changeset, :category_id, "ist intern")
      %Category{} -> changeset
    end
  end
end
