defmodule Abakus.Categories do
  @moduledoc """
  Category groups and categories with their assignments and targets, each the user's: functions take the caller's
  `%Scope{}` and see only its user's records; another user's behave like missing ones. Each user's internal group
  with Ready to Assign comes with its first use (`ready_to_assign!/1`).

  Deleted rows stay as tombstones (`deleted_at`). A deleted category has a successor, and whatever still points at
  it counts for that one, through chains (`successors/1`): its assignments add to the successor's, and so do the
  transactions that reach it later, so an amount assigned to the successor is what its own assignment and those
  of its predecessors add up to.
  """

  import Ecto.Query
  import Abakus.Owned

  alias Abakus.Categories.{
    Assignment,
    Category,
    CategoryGroup,
    TargetSnooze,
    TargetVersion
  }

  alias Abakus.{Budget, Ledger, Names, References, Repo, Successors, Sync}
  alias Abakus.Depot.BudgetLink, as: DepotLink
  alias Abakus.Kasse.BudgetLink
  alias Abakus.Users.Scope
  alias Ecto.Changeset

  @internal_group "Internal Master Category"

  @doc """
  Groups with their categories in budget order, without the internal ones; with `internal: true` the internal group
  with Ready to Assign comes first, as in YNAB's API.
  """
  def list_category_groups(%Scope{} = scope, opts \\ []) do
    internal? = Keyword.get(opts, :internal, false)
    if internal?, do: ready_to_assign!(scope)

    categories =
      from c in Category, where: ^internal? or not c.internal, order_by: [c.position, c.id]

    Repo.all(
      from g in alive(CategoryGroup, scope),
        where: ^internal? or not g.internal,
        order_by: [desc: g.internal, asc: g.position, asc: g.id],
        preload: [categories: ^categories]
    )
  end

  @doc """
  The internal category income is assigned to (UI: "Zu verteilen"), created with the user's internal group, under
  YNAB's names, when the user has none yet.
  """
  def ready_to_assign!(%Scope{} = scope) do
    Repo.one(internal(Category, scope)) || create_ready_to_assign!(scope)
  end

  defp internal(schema, scope), do: from(r in owned(schema, scope), where: r.internal)

  defp alive(schema, scope), do: from(r in owned(schema, scope), where: is_nil(r.deleted_at))

  # Conflicts leave what another process created meanwhile.
  defp create_ready_to_assign!(scope) do
    user_id = user_id(scope)

    Sync.insert!(%CategoryGroup{user_id: user_id, name: @internal_group, internal: true},
      on_conflict: :nothing
    )

    name = Category.ready_to_assign_name()

    Sync.insert!(
      %Category{
        user_id: user_id,
        category_group_id: Repo.one!(select(internal(CategoryGroup, scope), [g], g.id)),
        name: name,
        lookup_key: Names.lookup_key(name),
        internal: true
      },
      on_conflict: :nothing
    )

    Repo.one!(internal(Category, scope))
  end

  @doc "Creates a group; without a position it goes after the others."
  def create_category_group(%Scope{} = scope, attrs) do
    %CategoryGroup{user_id: user_id(scope)}
    |> CategoryGroup.changeset(attrs)
    |> put_next_position(fn -> alive(CategoryGroup, scope) end)
    |> Sync.insert()
  end

  @doc "Updates a group; one deleted meanwhile gives an error on `id`."
  def update_category_group(%Scope{} = scope, %CategoryGroup{} = group, attrs) do
    scope
    |> own!(group)
    |> CategoryGroup.changeset(attrs)
    |> update_alive(scope)
  end

  defp update_alive(%Changeset{data: %schema{id: id}} = changeset, scope) do
    if Repo.exists?(from r in alive(schema, scope), where: r.id == ^id),
      do: Sync.update(changeset, stale_error_field: :id),
      else:
        {:error,
         %{Changeset.add_error(changeset, :id, "is stale", stale: true) | action: :update}}
  end

  @doc "Creates a category; without a position it goes after the others in its group."
  def create_category(%Scope{} = scope, attrs) do
    changeset =
      %Category{user_id: user_id(scope)} |> Category.changeset(attrs) |> validate_group(scope)

    group_id = Changeset.get_field(changeset, :category_group_id)

    changeset
    |> put_next_position(fn ->
      from c in Category, where: c.category_group_id == ^group_id and is_nil(c.deleted_at)
    end)
    |> Sync.insert()
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
  def update_category(%Scope{} = scope, %Category{} = category, attrs) do
    scope
    |> own!(category)
    |> Category.changeset(attrs)
    |> validate_group(scope)
    |> update_alive(scope)
  end

  defp validate_group(changeset, scope) do
    with {:ok, group_id} <- Changeset.fetch_change(changeset, :category_group_id),
         %CategoryGroup{internal: false} <- Repo.get(alive(CategoryGroup, scope), group_id) do
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
  def delete_category_group(%Scope{} = scope, %CategoryGroup{id: id}) do
    Sync.write(fn -> scope |> deletable_group(id) |> delete_empty() end)
  end

  defp deletable_group(scope, id) do
    case Repo.get(alive(CategoryGroup, scope), id) do
      nil -> {:error, :not_found}
      %CategoryGroup{internal: true} -> {:error, :internal}
      group -> {:ok, group}
    end
  end

  defp delete_empty({:ok, %CategoryGroup{id: id} = group}) do
    if Repo.exists?(
         from c in Category, where: c.category_group_id == ^id and is_nil(c.deleted_at)
       ),
       do: {:error, :not_empty},
       else: group |> Changeset.change(deleted_at: DateTime.utc_now()) |> Sync.update()
  end

  defp delete_empty(error), do: error

  @doc """
  Deletes a category into the regular category `into`, its successor: its transactions, split lines, scheduled
  transactions and payees' last categories move there (`Abakus.Ledger.recategorize/4`), and so do the Kasse
  categories mapped to it (`Abakus.Kasse.BudgetLink.recategorize/3`) and the Depot's category for purchases
  (`Abakus.Depot.BudgetLink.recategorize/3`); its assignments stay and count for `into` (`successors/1`). Its
  targets and snoozes go. Reconciled transactions change too, so they need `reconciled: :confirmed` (see
  `reconciled_transactions?/2`).
  """
  def delete_category(%Scope{} = scope, %Category{id: id}, %Category{id: into_id}, opts \\ []) do
    Sync.write(fn ->
      with {:ok, category} <- deletable(scope, id),
           {:ok, into} <- target(scope, into_id, id),
           :ok <- Ledger.recategorize(scope, category.id, into.id, opts),
           :ok <- BudgetLink.recategorize(scope, category.id, into.id),
           :ok <- DepotLink.recategorize(scope, category.id, into.id) do
        Sync.delete_all(from v in TargetVersion, where: v.category_id == ^id)
        Sync.delete_all(from s in TargetSnooze, where: s.category_id == ^id)

        category
        |> Changeset.change(deleted_at: DateTime.utc_now(), successor_id: into.id)
        |> Sync.update()
      end
    end)
  end

  @doc "Whether deleting the category changes reconciled transactions."
  def reconciled_transactions?(%Scope{} = scope, %Category{id: id}),
    do: Ledger.reconciled_in_category?(scope, id)

  defp deletable(scope, id) do
    case Repo.get(alive(Category, scope), id) do
      nil -> {:error, :not_found}
      %Category{internal: true} -> {:error, :internal}
      category -> {:ok, category}
    end
  end

  defp target(_scope, id, id), do: {:error, :target}

  defp target(scope, into_id, _id) do
    case Repo.get(alive(Category, scope), into_id) do
      %Category{internal: false} = into -> {:ok, into}
      _internal_or_gone -> {:error, :target}
    end
  end

  @doc """
  The category each deleted category counts for: its successor, or that one's while it is deleted too. A chain
  that comes back to a category ends at the smallest id of its cycle.
  """
  def successors(%Scope{} = scope), do: Successors.of(scope, Category)

  @doc """
  Moves the Kasse categories mapped to the deleted categories `ids`, and the Depot's category for purchases, to the
  categories they count for (`successors/1`), as `delete_category/4` does, for categories another writer deleted.
  Returns `{:ok, nil}`.
  """
  def follow_deleted_categories(%Scope{} = scope, ids) do
    successors = successors(scope)

    for id <- Enum.uniq(ids), into_id = Map.get(successors, id, id), into_id != id do
      :ok = BudgetLink.recategorize(scope, id, into_id)
      :ok = DepotLink.recategorize(scope, id, into_id)
    end

    {:ok, nil}
  end

  @doc """
  Merges the regular categories `ids` that share their lookup key with others in their group, and those, into the
  oldest of them, the one with the smallest id (`delete_category/4`, reconciled transactions included).
  """
  def merge_duplicate_categories(%Scope{} = scope, ids) do
    groups =
      Repo.all(
        from c in alive(Category, scope),
          where: c.id in ^ids and not c.internal,
          select: {c.category_group_id, c.lookup_key},
          distinct: true
      )

    Enum.reduce_while(groups, :ok, fn {group_id, key}, :ok ->
      [into | merged] =
        Repo.all(
          from c in alive(Category, scope),
            where: c.category_group_id == ^group_id and c.lookup_key == ^key and not c.internal,
            order_by: c.id
        )

      case merge_categories(scope, merged, into) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp merge_categories(scope, merged, into) do
    Enum.reduce_while(merged, :ok, fn category, :ok ->
      case delete_category(scope, category, into, reconciled: :confirmed) do
        {:ok, _deleted} -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  @doc """
  Brings back what concurrent edits left without a place: a deleted category without a successor, the category a
  cycle of successors ends at (`successors/1`), and the deleted groups that still hold categories. Returns
  `{:ok, nil}`.
  """
  def revive_stranded(%Scope{} = scope) do
    stranded = for {id, id} <- successors(scope), do: id

    Sync.update_all(from(c in owned(Category, scope), where: c.id in ^stranded),
      set: [deleted_at: nil, successor_id: nil, updated_at: DateTime.utc_now()]
    )

    holding = from c in alive(Category, scope), select: c.category_group_id

    Sync.update_all(
      from(g in owned(CategoryGroup, scope),
        where: not is_nil(g.deleted_at) and g.id in subquery(holding)
      ),
      set: [deleted_at: nil, updated_at: DateTime.utc_now()]
    )

    {:ok, nil}
  end

  @doc """
  Finds a category by name, ignoring emoji and case; two regular categories with the same name are ambiguous. An
  internal category's name means it alone.
  """
  def find_category_by_name(%Scope{} = scope, name) when is_binary(name) do
    key = Names.lookup_key(name)

    Repo.all(from c in alive(Category, scope), where: c.lookup_key == ^key)
    |> Enum.map(&{&1, &1.internal})
    |> Names.pick()
  end

  @doc """
  Sets the amount assigned to a category in a month (any day of it), its own assignment taking what its deleted
  predecessors have assigned then into account. Never refused for lack of money, as in YNAB: Ready to Assign may go
  below zero (see `Abakus.Budget`).
  """
  def assign(%Scope{} = scope, %Category{} = category, month, amount) do
    Sync.write(fn ->
      %Assignment{category_id: category.id, user_id: user_id(scope)}
      |> Assignment.changeset(%{month: month, amount: amount})
      |> validate_regular(scope, category)
      |> less_predecessors(scope)
      |> upsert_assignment()
    end)
  end

  defp less_predecessors(%Changeset{valid?: false} = changeset, _scope), do: changeset

  defp less_predecessors(changeset, scope) do
    category_id = Changeset.get_field(changeset, :category_id)
    month = Changeset.get_field(changeset, :month)

    predecessors =
      for {id, ^category_id} <- successors(scope), id != category_id, do: id

    assigned =
      Repo.one(
        from a in alive(Assignment, scope),
          where: a.category_id in ^predecessors and a.month == ^month,
          select: coalesce(sum(a.amount), 0)
      )

    Changeset.update_change(changeset, :amount, &(&1 - assigned))
  end

  defp upsert_assignment(changeset) do
    Sync.insert(changeset,
      on_conflict: {:replace, [:amount, :deleted_at, :updated_at]},
      conflict_target: [:category_id, :month],
      returning: true
    )
  end

  @doc """
  The budget's data for `Abakus.Budget`: every regular category in budget order, with what points at a deleted
  category counted for its successor (`successors/1`).
  """
  def budget(%Scope{} = scope) do
    ready_to_assign_id = ready_to_assign!(scope).id
    successors = successors(scope)
    resolve = fn {{id, month}, amount} -> {{Map.get(successors, id, id), month}, amount} end

    {income, activity} =
      scope
      |> Ledger.budget_activity()
      |> Enum.map(resolve)
      |> Enum.split_with(fn {{id, _month}, _} -> id == ready_to_assign_id end)

    assigned =
      Repo.all(from a in alive(Assignment, scope), select: {{a.category_id, a.month}, a.amount})

    %Budget{
      categories: budget_categories(scope),
      income: sum_by_key(Enum.map(income, fn {{_id, month}, amount} -> {month, amount} end)),
      activity: sum_by_key(activity),
      assigned: assigned |> Enum.map(resolve) |> sum_by_key(),
      targets: Enum.group_by(Repo.all(alive(TargetVersion, scope)), & &1.category_id),
      snoozes:
        MapSet.new(
          Repo.all(from s in alive(TargetSnooze, scope), select: {s.category_id, s.month})
        )
    }
  end

  defp sum_by_key(pairs) do
    Enum.reduce(pairs, %{}, fn {key, amount}, sums ->
      Map.update(sums, key, amount, &(&1 + amount))
    end)
  end

  defp budget_categories(scope) do
    Repo.all(
      from c in alive(Category, scope),
        join: g in assoc(c, :category_group),
        where: not c.internal and is_nil(g.deleted_at),
        order_by: [g.position, g.id, c.position, c.id],
        select: %{id: c.id}
    )
  end

  @doc """
  Moves an amount assigned in a month (any day of it) from one category to another, `:ready_to_assign` standing
  for Zu verteilen on either side; never refused for lack of money, as `assign/4`. Returns `{:ok, amount}`.
  """
  def move_assigned(%Scope{} = scope, from, to, month, amount) do
    month = month!(month)

    Sync.write(fn ->
      with {:ok, _from} <- add_assigned(scope, from, month, -amount),
           {:ok, _to} <- add_assigned(scope, to, month, amount),
           do: {:ok, amount}
    end)
  end

  defp add_assigned(_scope, :ready_to_assign, _month, _amount), do: {:ok, nil}

  defp add_assigned(scope, %Category{id: id} = category, month, amount) do
    ids = [id | for({predecessor, ^id} <- successors(scope), do: predecessor)]

    assigned =
      Repo.one(
        from a in alive(Assignment, scope),
          where: a.category_id in ^ids and a.month == ^month,
          select: coalesce(sum(a.amount), 0)
      )

    assign(scope, category, month, assigned + amount)
  end

  @doc """
  Takes back what the categories, or only `category`, have assigned in a month (any day of it), with their deleted
  predecessors, so it goes back to Zu verteilen.
  """
  def reset_assignments(%Scope{} = scope, month, category \\ nil) do
    month = month!(month)

    ids =
      if category,
        do: [category.id],
        else: for(%{id: id} <- budget_categories(scope), do: id)

    ids =
      ids ++ for {predecessor, successor} <- successors(scope), successor in ids, do: predecessor

    Sync.delete_all(
      from a in owned(Assignment, scope), where: a.month == ^month and a.category_id in ^ids
    )

    :ok
  end

  @doc """
  Fills the month's underfunded categories, or only `category`, from Ready to Assign
  (`Abakus.Budget.fill_underfunded/4`); `current` is the current month, both any day of it. Returns the new
  assignments as `{category_id, amount}`.
  """
  def fill_underfunded(%Scope{} = scope, month, current, category \\ nil) do
    month = month!(month)

    Sync.write(fn ->
      fills =
        Budget.fill_underfunded(budget(scope), month, month!(current), category && category.id)

      with :ok <- put_assignments(scope, fills, month), do: {:ok, fills}
    end)
  end

  defp put_assignments(scope, fills, month) do
    Enum.reduce_while(fills, :ok, fn {category_id, amount}, :ok ->
      %Assignment{category_id: category_id, user_id: user_id(scope)}
      |> Assignment.changeset(%{month: month, amount: amount})
      |> less_predecessors(scope)
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
  def set_target(%Scope{} = scope, %Category{} = category, attrs) do
    %TargetVersion{category_id: category.id, user_id: user_id(scope)}
    |> TargetVersion.changeset(attrs)
    |> validate_regular(scope, category)
    |> Sync.insert(
      on_conflict:
        {:replace,
         [:cadence, :amount, :due_on, :repeats_yearly, :set_aside, :deleted_at, :updated_at]},
      conflict_target: [:category_id, :from_month],
      returning: true
    )
  end

  @doc "The target version in effect in a month (any day of it), or nil if the category has no target then."
  def target_for(%Scope{} = scope, %Category{id: category_id}, month) do
    month = month!(month)

    version =
      Repo.one(
        from v in alive(TargetVersion, scope),
          where: v.category_id == ^category_id and v.from_month <= ^month,
          order_by: [desc: v.from_month],
          limit: 1
      )

    if version && TargetVersion.complete?(version), do: version
  end

  @doc "Snoozes a category's target in a month (any day of it); snoozing it again returns the snooze there is."
  def snooze_target(%Scope{} = scope, %Category{} = category, month) do
    %TargetSnooze{category_id: category.id, user_id: user_id(scope)}
    |> TargetSnooze.changeset(%{month: month})
    |> validate_regular(scope, category)
    |> Sync.insert(
      on_conflict: {:replace, [:month, :deleted_at]},
      conflict_target: [:category_id, :month],
      returning: true
    )
  end

  def unsnooze_target(%Scope{} = scope, %Category{} = category, month) do
    Sync.delete_all(snoozes(scope, category, month))
    :ok
  end

  def target_snoozed?(%Scope{} = scope, %Category{} = category, month),
    do: Repo.exists?(snoozes(scope, category, month))

  defp snoozes(scope, %Category{id: category_id}, month) do
    month = month!(month)

    from s in alive(TargetSnooze, scope),
      where: s.category_id == ^category_id and s.month == ^month
  end

  defp month!(value) do
    case Ecto.Type.cast(:date, value) do
      {:ok, %Date{} = date} -> Date.beginning_of_month(date)
      _ -> raise ArgumentError, "not a date: #{inspect(value)}"
    end
  end

  # Looks the category up again, so a stale struct gives an error instead of a constraint error.
  defp validate_regular(changeset, scope, %Category{id: id}) do
    case Repo.get(alive(Category, scope), id) do
      nil -> References.not_found(changeset, :category_id)
      %Category{internal: true} -> Changeset.add_error(changeset, :category_id, "ist intern")
      %Category{} -> changeset
    end
  end
end
