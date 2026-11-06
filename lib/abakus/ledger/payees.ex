defmodule Abakus.Ledger.Payees do
  @moduledoc """
  Managing the regular payees as the apps do ("Empfänger verwalten"): renaming, combining and hiding them and editing
  their rename rules (`Abakus.Ledger.PayeeRenameCondition`), each the scope's user's and written through
  `Abakus.Sync`.

  Renaming a payee to the name of another regular payee merges it into that one, which takes over its rules. The old
  name becomes an "is" rule of the payee it now goes by, and no other payee keeps such a rule, unless only the
  capitalisation changed or that payee's rules match the old name already.

  A payee that is gone, a transfer payee or another user's is `{:error, :not_found}`.
  """

  import Abakus.Owned
  import Ecto.Query

  alias Abakus.{Ledger, Names, Repo, Sync}

  alias Abakus.Ledger.{
    Payee,
    PayeeRenameCondition,
    ScheduledSubtransaction,
    ScheduledTransaction,
    Subtransaction
  }

  alias Abakus.Users.Scope
  alias Ecto.Changeset

  @doc """
  The regular payees by name, hidden ones too, each as `%{payee, rename_conditions, transaction_count, scheduled}`:
  its rules in order, how many transactions in the register and scheduled transactions use it, in a part too, and
  whether scheduled ones are among them.
  """
  def list(%Scope{} = scope) do
    conditions = scope |> live_conditions() |> Repo.all() |> Enum.group_by(& &1.payee_id)
    {_register, scheduled} = counts = counts(scope, :transactions)
    counts = total(counts)

    for payee <- Repo.all(from p in regular(scope), order_by: [p.lookup_key, p.id]) do
      %{
        payee: payee,
        rename_conditions: Map.get(conditions, payee.id, []),
        transaction_count: Map.get(counts, payee.id, 0),
        scheduled: Map.has_key?(scheduled, payee.id)
      }
    end
  end

  @doc """
  Renames a regular payee, merging it into the regular payee with the name's lookup key if there is one, and returns
  the payee that now has the name. Refuses a blank name and one that starts with "Transfer :".
  """
  def rename(%Scope{} = scope, %Payee{} = payee, name) do
    Sync.write(fn ->
      with {:ok, payee} <- fetch(scope, payee), do: rename_live(scope, payee, name)
    end)
  end

  defp rename_live(scope, payee, name) do
    changeset = payee |> Payee.changeset(%{name: trim(name)}) |> validate_name()

    cond do
      not changeset.valid? -> Changeset.apply_action(changeset, :update)
      changeset.changes == %{} -> {:ok, payee}
      true -> {:ok, rename_valid(scope, payee, changeset)}
    end
  end

  defp rename_valid(scope, payee, changeset) do
    key = Changeset.get_field(changeset, :lookup_key)

    case Repo.one(from p in regular(scope), where: p.lookup_key == ^key and p.id != ^payee.id) do
      nil ->
        renamed = Sync.update!(changeset)
        if key != payee.lookup_key, do: record_rule(scope, payee.name, renamed)
        renamed

      into ->
        merge_into(scope, payee, into)
    end
  end

  @doc """
  Combines the regular payees `ids` under the name, renaming each in turn as `rename/3` does, and returns the payee
  that has the name, nil without a regular payee among them. Refuses a name `rename/3` refuses.
  """
  def combine(%Scope{} = scope, ids, name) do
    name = trim(name)

    Sync.write(fn ->
      with {:ok, _valid} <-
             %Payee{user_id: user_id(scope)}
             |> Payee.changeset(%{name: name})
             |> validate_name()
             |> Changeset.apply_action(:update),
           do: rename_each(scope, ids, name)
    end)
  end

  defp rename_each(scope, ids, name) do
    by_id = Map.new(Repo.all(from p in regular(scope), where: p.id in ^ids), &{&1.id, &1})

    ids
    |> Enum.uniq()
    |> Enum.flat_map(&List.wrap(by_id[&1]))
    |> Enum.reduce({:ok, nil}, fn
      payee, {:ok, _combined} -> rename(scope, payee, name)
      _payee, error -> error
    end)
  end

  defp trim(name), do: String.trim(name || "")

  defp validate_name(changeset) do
    Changeset.validate_change(changeset, :name, fn :name, name ->
      if transfer_name?(name),
        do: [
          name:
            "„#{name}“ ist kein gültiger Empfängername. „Transfer :“ am Anfang ist Umbuchungen vorbehalten."
        ],
        else: []
    end)
  end

  defp transfer_name?(name),
    do: name |> String.replace(" ", "") |> String.downcase() |> String.starts_with?("transfer:")

  @doc "Hides (`true`) or shows the regular payees `ids`; transfer payees stay as they are."
  def set_hidden(%Scope{} = scope, ids, hidden) when is_boolean(hidden) do
    Sync.update_all(
      from(p in regular(scope), where: p.id in ^ids and p.hidden != ^hidden),
      set: [hidden: hidden, updated_at: DateTime.utc_now()]
    )

    :ok
  end

  @doc """
  Replaces the payee's rename rules by `conditions` in their order: maps with `operator` and `text`, and the `id` of
  one the payee has. Blank ones are dropped, the payee's others deleted. Returns the rules as stored.
  """
  def put_rename_conditions(%Scope{} = scope, %Payee{} = payee, conditions) do
    Sync.write(fn ->
      with {:ok, payee} <- fetch(scope, payee), do: replace_conditions(scope, payee, conditions)
    end)
  end

  defp replace_conditions(scope, payee, conditions) do
    existing = Map.new(conditions_of(scope, payee.id), &{&1.id, &1})

    with {:ok, stored} <-
           conditions
           |> Enum.reject(&PayeeRenameCondition.blank?(attr(&1, :text)))
           |> Enum.with_index()
           |> collect(fn {attrs, position} ->
             store_condition(payee, existing[attr(attrs, :id)], attrs, position)
           end) do
      kept = MapSet.new(stored, & &1.id)
      delete_conditions(for id <- Map.keys(existing), id not in kept, do: id)
      {:ok, stored}
    end
  end

  defp store_condition(payee, nil, attrs, position) do
    %PayeeRenameCondition{user_id: payee.user_id, payee_id: payee.id}
    |> PayeeRenameCondition.changeset(condition_attrs(attrs, position))
    |> Sync.insert()
  end

  defp store_condition(_payee, condition, attrs, position),
    do:
      condition
      |> PayeeRenameCondition.changeset(condition_attrs(attrs, position))
      |> Sync.update()

  defp condition_attrs(attrs, position),
    do: %{operator: attr(attrs, :operator), text: attr(attrs, :text), position: position}

  defp attr(attrs, key), do: Map.get(attrs, key, Map.get(attrs, Atom.to_string(key)))

  defp collect(items, fun) do
    items
    |> Enum.reduce_while({:ok, []}, fn item, {:ok, done} ->
      case fun.(item) do
        {:ok, result} -> {:cont, {:ok, [result | done]}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, done} -> {:ok, Enum.reverse(done)}
      error -> error
    end
  end

  @doc """
  What "Bestehende Buchungen umbenennen" would rename to the payee, as `{:ok, %{transaction_count, payee_names,
  payee_ids}}`: the other regular payees its rules match, those nothing uses too, by name as the apps sort them, and
  how often transactions in the register and scheduled transactions use them, each part on its own.
  """
  def rename_preview(%Scope{} = scope, %Payee{} = payee) do
    with {:ok, payee} <- fetch(scope, payee) do
      matched = Enum.sort_by(matched(scope, payee), &name_order(elem(&1, 0).name))

      {:ok,
       %{
         transaction_count: matched |> Enum.map(&elem(&1, 1)) |> Enum.sum(),
         payee_names: Enum.map(matched, &elem(&1, 0).name),
         payee_ids: Enum.map(matched, &elem(&1, 0).id)
       }}
    end
  end

  # Like the apps' localizedCaseInsensitiveCompare: diacritics and case only break ties.
  defp name_order(name) do
    lower = name |> :unicode.characters_to_nfd_binary() |> String.downcase()
    {String.replace(lower, ~r/\p{Mn}/u, ""), lower, name}
  end

  @doc """
  Merges the payees `rename_preview/2` finds into the payee and returns it, if they are still the previewed
  `payee_ids`; `{:error, :changed}` if not.
  """
  def apply_rename_rules(%Scope{} = scope, %Payee{} = payee, payee_ids) do
    Sync.write(fn ->
      with {:ok, payee} <- fetch(scope, payee), do: merge_matched(scope, payee, payee_ids)
    end)
  end

  defp merge_matched(scope, payee, payee_ids) do
    matched = matched(scope, payee)

    if Enum.sort(Enum.map(matched, &elem(&1, 0).id)) == Enum.sort(payee_ids),
      do:
        {:ok,
         Enum.reduce(matched, payee, fn {from, _uses}, into -> merge_into(scope, from, into) end)},
      else: {:error, :changed}
  end

  defp matched(scope, target) do
    conditions = conditions_of(scope, target.id)
    uses = scope |> counts(:uses) |> total()

    for payee <- Repo.all(from p in regular(scope), where: p.id != ^target.id),
        not transfer_name?(payee.name),
        applies?(target, conditions, payee.name),
        do: {payee, Map.get(uses, payee.id, 0)}
  end

  defp applies?(payee, conditions, name),
    do:
      Names.lookup_key(name) == payee.lookup_key or
        Enum.any?(conditions, &PayeeRenameCondition.matches?(&1, name))

  defp merge_into(scope, from, into) do
    {kept, duplicates} =
      scope
      |> conditions_of(from.id)
      |> Enum.reduce({conditions_of(scope, into.id), []}, fn condition, {kept, duplicates} ->
        if Enum.any?(kept, &PayeeRenameCondition.equivalent?(&1, condition)),
          do: {kept, [condition.id | duplicates]},
          else: {kept ++ [condition], duplicates}
      end)

    delete_conditions(duplicates)

    kept
    |> Enum.with_index()
    |> Enum.each(fn {condition, position} ->
      Sync.update!(Changeset.change(condition, payee_id: into.id, position: position))
    end)

    into = Ledger.merge_payee(scope, from, into)
    record_rule(scope, from.name, into)
    into
  end

  defp record_rule(scope, old_name, into) do
    rule = %PayeeRenameCondition{operator: :is, text: old_name}

    scope
    |> live_conditions()
    |> Repo.all()
    |> Enum.filter(&(&1.payee_id != into.id and PayeeRenameCondition.equivalent?(&1, rule)))
    |> Enum.map(& &1.id)
    |> delete_conditions()

    conditions = conditions_of(scope, into.id)

    unless applies?(into, conditions, old_name) do
      %PayeeRenameCondition{user_id: into.user_id, payee_id: into.id}
      |> PayeeRenameCondition.changeset(%{
        operator: :is,
        text: old_name,
        position: conditions |> Enum.map(& &1.position) |> Enum.max(fn -> -1 end) |> Kernel.+(1)
      })
      |> Sync.insert!()
    end
  end

  defp delete_conditions([]), do: :ok

  defp delete_conditions(ids),
    do: Sync.delete_all(from(c in PayeeRenameCondition, where: c.id in ^ids))

  # Splits count once per transaction for :transactions, and once per part for :uses, as in the apps.
  defp counts(scope, kind) do
    scheduled = from s in owned(ScheduledTransaction, scope), where: is_nil(s.deleted_at)

    {payee_counts(Ledger.in_register(scope), Subtransaction, :transaction_id, kind),
     payee_counts(scheduled, ScheduledSubtransaction, :scheduled_transaction_id, kind)}
  end

  defp total({register, scheduled}),
    do: Map.merge(register, scheduled, fn _payee_id, one, other -> one + other end)

  defp payee_counts(parents, part_schema, parent_field, kind) do
    own =
      from t in parents, where: not is_nil(t.payee_id), select: %{payee_id: t.payee_id, id: t.id}

    parts =
      from s in part_schema,
        join: t in subquery(parents),
        on: field(s, ^parent_field) == t.id,
        where: is_nil(s.deleted_at) and not is_nil(s.payee_id),
        select: %{payee_id: s.payee_id, id: t.id}

    rows = if kind == :transactions, do: union(own, ^parts), else: union_all(own, ^parts)

    Repo.all(from r in subquery(rows), group_by: r.payee_id, select: {r.payee_id, count(r.id)})
    |> Map.new()
  end

  defp regular(scope),
    do:
      from(p in owned(Payee, scope),
        where: is_nil(p.deleted_at) and is_nil(p.transfer_account_id)
      )

  defp fetch(scope, %Payee{id: id}) do
    case Repo.get(regular(scope), id) do
      nil -> {:error, :not_found}
      payee -> {:ok, payee}
    end
  end

  defp live_conditions(scope),
    do:
      from(c in owned(PayeeRenameCondition, scope),
        where: is_nil(c.deleted_at),
        order_by: [c.payee_id, c.position, c.id]
      )

  defp conditions_of(scope, payee_id),
    do: Repo.all(from c in live_conditions(scope), where: c.payee_id == ^payee_id)
end
