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

  alias Abakus.{Budget, Ledger, Names, References, Repo}
  alias Ecto.Changeset

  @doc """
  Groups with their categories in budget order, without the internal ones; with `internal: true` the internal group
  with Ready to Assign comes first, as in YNAB's API.
  """
  def list_category_groups(opts \\ []) do
    internal? = Keyword.get(opts, :internal, false)

    categories =
      from c in Category, where: ^internal? or not c.internal, order_by: [c.position, c.id]

    Repo.all(
      from g in CategoryGroup,
        where: ^internal? or not g.internal,
        order_by: [desc: g.internal, asc: g.position, asc: g.id],
        preload: [categories: ^categories]
    )
  end

  @doc "The internal category income is assigned to (UI: \"Zu verteilen\")."
  def ready_to_assign! do
    Repo.one!(
      from c in Category, where: c.internal and c.name == ^Category.ready_to_assign_name()
    )
  end

  @doc "Creates a group; without a position it goes after the others."
  def create_category_group(attrs) do
    %CategoryGroup{}
    |> CategoryGroup.changeset(attrs)
    |> put_next_position(fn -> CategoryGroup end)
    |> Repo.insert()
  end

  @doc "Updates a group; one deleted meanwhile gives an error on `id`."
  def update_category_group(%CategoryGroup{} = group, attrs) do
    group
    |> CategoryGroup.changeset(attrs)
    |> Repo.update(stale_error_field: :id)
  end

  @doc "Creates a category; without a position it goes after the others in its group."
  def create_category(attrs) do
    changeset = %Category{} |> Category.changeset(attrs) |> validate_group()
    group_id = Changeset.get_field(changeset, :category_group_id)

    changeset
    |> put_next_position(fn -> from c in Category, where: c.category_group_id == ^group_id end)
    |> Repo.insert()
  end

  # Cast params have string keys; a given 0 counts as given, though it changes nothing.
  defp put_next_position(changeset, siblings) do
    if Map.has_key?(changeset.params, "position") or not changeset.valid?,
      do: changeset,
      else: Changeset.put_change(changeset, :position, next_position(siblings.()))
  end

  defp next_position(siblings),
    do: Repo.one(from s in siblings, select: coalesce(max(s.position) + 1, 0))

  @doc "Updates a category; one deleted meanwhile gives an error on `id`."
  def update_category(%Category{} = category, attrs) do
    category
    |> Category.changeset(attrs)
    |> validate_group()
    |> Repo.update(stale_error_field: :id)
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

  @doc "Deletes a group without categories; the internal one stays."
  def delete_category_group(%CategoryGroup{id: id}) do
    Repo.transact(fn -> id |> deletable_group() |> delete_empty() end)
  end

  defp deletable_group(id) do
    case Repo.get(CategoryGroup, id) do
      nil -> {:error, :not_found}
      %CategoryGroup{internal: true} -> {:error, :internal}
      group -> {:ok, group}
    end
  end

  defp delete_empty({:ok, %CategoryGroup{id: id} = group}) do
    if Repo.exists?(from c in Category, where: c.category_group_id == ^id),
      do: {:error, :not_empty},
      else: Repo.delete(group)
  end

  defp delete_empty(error), do: error

  @doc """
  Deletes a category and moves everything it has into the regular category `into`: its transactions, split lines and
  payees' last categories (`Abakus.Ledger.recategorize/3`), and its assignments, added to those of `into` per month.
  Its targets and snoozes go. Reconciled transactions change too, so they need `reconciled: :confirmed`
  (see `reconciled_transactions?/1`).
  """
  def delete_category(%Category{id: id}, %Category{id: into_id}, opts \\ []) do
    Repo.transact(fn ->
      with {:ok, category} <- deletable(id),
           {:ok, into} <- target(into_id, id),
           :ok <- Ledger.recategorize(category.id, into.id, opts),
           :ok <- move_assignments(category, into) do
        Repo.delete_all(from v in TargetVersion, where: v.category_id == ^id)
        Repo.delete_all(from s in TargetSnooze, where: s.category_id == ^id)
        Repo.delete(category)
      end
    end)
  end

  @doc "Whether deleting the category changes reconciled transactions."
  def reconciled_transactions?(%Category{id: id}), do: Ledger.reconciled_in_category?(id)

  defp deletable(id) do
    case Repo.get(Category, id) do
      nil -> {:error, :not_found}
      %Category{internal: true} -> {:error, :internal}
      category -> {:ok, category}
    end
  end

  defp target(id, id), do: {:error, :target}

  defp target(into_id, _id) do
    case Repo.get(Category, into_id) do
      %Category{internal: false} = into -> {:ok, into}
      _internal_or_gone -> {:error, :target}
    end
  end

  defp move_assignments(%Category{id: id}, %Category{id: into_id}) do
    moved = Repo.all(from a in Assignment, where: a.category_id == ^id)

    held =
      Map.new(
        Repo.all(from a in Assignment, where: a.category_id == ^into_id),
        &{&1.month, &1.amount}
      )

    Repo.delete_all(from a in Assignment, where: a.category_id == ^id)

    moved
    |> Enum.map(&{into_id, &1.month, &1.amount + Map.get(held, &1.month, 0)})
    |> put_assignments()
  end

  @doc """
  Finds a category by name, ignoring emoji and case; two regular categories with the same name are ambiguous. An
  internal category's name means it alone.
  """
  def find_category_by_name(name) when is_binary(name) do
    key = Names.lookup_key(name)

    Repo.all(from c in Category, where: c.lookup_key == ^key)
    |> Enum.map(&{&1, &1.internal})
    |> Names.pick()
  end

  @doc """
  Sets the amount assigned to a category in a month (any day of it). Never refused for lack of money, as in YNAB:
  Ready to Assign may go below zero (see `Abakus.Budget`).
  """
  def assign(%Category{} = category, month, amount) do
    %Assignment{category_id: category.id}
    |> Assignment.changeset(%{month: month, amount: amount})
    |> validate_regular(category)
    |> upsert_assignment()
  end

  defp upsert_assignment(changeset) do
    Repo.insert(changeset,
      on_conflict: {:replace, [:amount, :updated_at]},
      conflict_target: [:category_id, :month],
      returning: true
    )
  end

  @doc "The budget's data for `Abakus.Budget`: every regular category in budget order."
  def budget do
    ready_to_assign_id = ready_to_assign!().id

    {income, activity} =
      Enum.split_with(Ledger.budget_activity(), fn {{id, _month}, _} ->
        id == ready_to_assign_id
      end)

    %Budget{
      categories: budget_categories(),
      income: Map.new(income, fn {{_id, month}, amount} -> {month, amount} end),
      activity: Map.new(activity),
      assigned:
        Map.new(Repo.all(from a in Assignment, select: {{a.category_id, a.month}, a.amount})),
      targets: Enum.group_by(Repo.all(TargetVersion), & &1.category_id),
      snoozes: MapSet.new(Repo.all(from s in TargetSnooze, select: {s.category_id, s.month}))
    }
  end

  @doc "Income (Ready to Assign's activity) per `{payee_name, month}`, `nil` without a payee."
  def income_by_payee, do: Ledger.category_activity_by_payee(ready_to_assign!().id)

  defp budget_categories do
    Repo.all(
      from c in Category,
        join: g in assoc(c, :category_group),
        where: not c.internal,
        order_by: [g.position, g.id, c.position, c.id],
        select: %{id: c.id}
    )
  end

  @doc """
  Moves an amount assigned in a month (any day of it) from one category to another, `:ready_to_assign` standing
  for Zu verteilen on either side; never refused for lack of money, as `assign/3`. Returns `{:ok, amount}`.
  """
  def move_assigned(from, to, month, amount) do
    month = month!(month)

    Repo.transact(fn ->
      with {:ok, _from} <- add_assigned(from, month, -amount),
           {:ok, _to} <- add_assigned(to, month, amount),
           do: {:ok, amount}
    end)
  end

  defp add_assigned(:ready_to_assign, _month, _amount), do: {:ok, nil}

  defp add_assigned(%Category{id: id} = category, month, amount) do
    assigned =
      Repo.one(
        from a in Assignment, where: a.category_id == ^id and a.month == ^month, select: a.amount
      )

    assign(category, month, (assigned || 0) + amount)
  end

  @doc """
  Takes back what the categories, or only `category`, have assigned in a month (any day of it), so it goes
  back to Zu verteilen.
  """
  def reset_assignments(month, category \\ nil) do
    month = month!(month)

    ids =
      if category,
        do: [category.id],
        else: for(%{id: id} <- budget_categories(), do: id)

    Repo.delete_all(from a in Assignment, where: a.month == ^month and a.category_id in ^ids)
    :ok
  end

  @doc """
  Fills the month's underfunded categories, or only `category`, from Ready to Assign
  (`Abakus.Budget.fill_underfunded/4`); `current` is the current month, both any day of it. Returns the new
  assignments as `{category_id, amount}`.
  """
  def fill_underfunded(month, current, category \\ nil) do
    month = month!(month)

    Repo.transact(fn ->
      fills = Budget.fill_underfunded(budget(), month, month!(current), category && category.id)
      with :ok <- put_assignments(in_month(fills, month)), do: {:ok, fills}
    end)
  end

  defp in_month(fills, month), do: Enum.map(fills, fn {id, amount} -> {id, month, amount} end)

  defp put_assignments(assignments) do
    Enum.reduce_while(assignments, :ok, fn {category_id, month, amount}, :ok ->
      %Assignment{category_id: category_id}
      |> Assignment.changeset(%{month: month, amount: amount})
      |> upsert_assignment()
      |> case do
        {:ok, _assignment} -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  @doc """
  Sets a category's target from a month on (attrs: `from_month`, any day of it, `cadence`, `amount`, `due_on`,
  `repeats_yearly`, `set_aside`); replaces a version that starts in the same month. Cadence `none` removes the
  target from that month on.
  """
  def set_target(%Category{} = category, attrs) do
    %TargetVersion{category_id: category.id}
    |> TargetVersion.changeset(attrs)
    |> validate_regular(category)
    |> Repo.insert(
      on_conflict:
        {:replace, [:cadence, :amount, :due_on, :repeats_yearly, :set_aside, :updated_at]},
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
