defmodule Abakus.Sync.Incoming do
  @moduledoc """
  Applies a device's messages (`sync/PROTOCOL.md`) in one database transaction, foreign keys checked at its end so
  rows may come in any order; a push that leaves a row pointing at none is refused whole, and so is one with a clock
  more than five minutes ahead of the server's time, as that clock would outrun every other writer's. Messages for
  tables or columns the server does not sync are ignored, and so is one already stored with the same clock for the
  same field. The rest are stored; a message for a row of another user, or pointing at one, is dropped. A message
  changes its field when its clock is newer than the field's, unless the field is not the device's to change
  (`Abakus.Sync.Authority`); a row that does not exist yet is created with the fields its messages bring and belongs
  to the scope's user.

  Then the server settles what the rules need, writing like any writer: it writes the refused fields again and
  deletes the parts added to a led transaction; an account without its transfer payee gets one; payees, or
  categories in one group, that the messages created, renamed or moved and that share a lookup key with another one
  are merged into the oldest; what the messages point at a merged payee points at the end of its chain of
  successors; a deleted category without a successor or ending a cycle of successors, and a group still holding
  categories, come back; and the Kasse's and the Depot's links leave the categories the messages deleted.
  """

  import Ecto.Query

  alias Abakus.{Categories, Ids, Ledger, LocalTime, Names, Repo, Sync}
  alias Abakus.Categories.Category
  alias Abakus.Ledger.{Account, Payee}
  alias Abakus.Sync.{Authority, Clock, FieldClock, Message, Tables}
  alias Abakus.Users.Scope

  @ahead_ms 5 * 60 * 1000

  @doc "Applies the messages; `{:ok, stored}` with how many were stored, else `{:error, reason}`."
  def apply(_scope, _device, []), do: {:ok, 0}

  def apply(%Scope{user: %{id: user_id}} = scope, device, messages) do
    with {:ok, parsed} <- parse(messages, device),
         do: Repo.transact(fn -> apply_parsed(scope, user_id, parsed) end)
  rescue
    error in [Exqlite.Error, Ecto.ConstraintError] ->
      {:error, {:rejected, Exception.message(error)}}
  end

  defp apply_parsed(scope, user_id, parsed) do
    Repo.query!("PRAGMA defer_foreign_keys = ON")

    fresh =
      parsed
      |> Enum.uniq_by(&key/1)
      |> reject_stored()
      |> owned_by(user_id)
      |> pointing_at_own(user_id)

    Sync.store_messages(Enum.map(fresh, &Map.put(&1, :user_id, user_id)))

    {applied, refused, undone} = fresh |> winners() |> Authority.check()
    touched = applied |> put_rows(user_id) |> Enum.flat_map(&touched/1)
    Sync.put_field_clocks(applied)

    with {:ok, _settled} <- settle(scope, applied, touched, refused, undone),
         :ok <- check_references(applied),
         do: {:ok, length(fresh)}
  end

  defp check_references(applied) do
    applied
    |> Enum.map(& &1.table)
    |> Enum.uniq()
    |> Enum.flat_map(&Repo.query!("PRAGMA foreign_key_check(#{&1})").rows)
    |> case do
      [] ->
        :ok

      [[table, _rowid, parent, _key] | _more] ->
        {:error, {:rejected, "#{table} points at a missing row of #{parent}"}}
    end
  end

  defp parse(messages, device) do
    latest = DateTime.to_unix(LocalTime.utc_now(), :millisecond) + @ahead_ms

    messages
    |> Enum.reduce_while({:ok, []}, fn message, {:ok, parsed} ->
      case parse_message(message, device, latest) do
        {:ok, nil} -> {:cont, {:ok, parsed}}
        {:ok, message} -> {:cont, {:ok, [message | parsed]}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, parsed} -> {:ok, Enum.reverse(parsed)}
      error -> error
    end
  end

  defp parse_message(
         %{
           "table" => table,
           "row_id" => row_id,
           "column" => column,
           "value" => value,
           "clock" => clock
         },
         device,
         latest
       ) do
    with :ok <- check_clock(clock, device, latest),
         {:ok, row_id} <- parse_row_id(row_id) do
      known(
        Tables.schema(table),
        column,
        %{row_id: row_id, clock: clock, device: device},
        value
      )
    end
  end

  defp parse_message(message, _device, _latest), do: {:error, {:invalid_message, message}}

  defp check_clock(clock, device, latest) do
    case Clock.parse(clock) do
      {:ok, %Clock{device: ^device, millis: millis}} when millis > latest ->
        {:error, {:clock_ahead, clock}}

      {:ok, %Clock{device: ^device}} ->
        :ok

      _other ->
        {:error, {:invalid_clock, clock}}
    end
  end

  defp parse_row_id(row_id) do
    case Ids.cast(row_id) do
      {:ok, id} -> {:ok, id}
      :error -> {:error, {:invalid_row_id, row_id}}
    end
  end

  defp known(nil = _schema, _column, _origin, _value), do: {:ok, nil}

  defp known(schema, column, origin, value) do
    case Tables.column(schema, column) do
      nil -> {:ok, nil}
      field -> decoded(schema, field, origin, value)
    end
  end

  defp decoded(schema, field, origin, value) do
    case Tables.decode(schema, field, value) do
      {:ok, decoded} ->
        {:ok,
         Map.merge(origin, %{
           schema: schema,
           table: Tables.table(schema),
           field: field,
           column: Atom.to_string(field),
           value: value,
           decoded: decoded
         })}

      :error ->
        {:error, {:invalid_value, Tables.table(schema), Atom.to_string(field), value}}
    end
  end

  defp key(message), do: {message.clock, message.table, message.row_id, message.column}

  defp reject_stored(messages) do
    stored =
      messages
      |> Enum.map(& &1.clock)
      |> Enum.uniq()
      |> Enum.chunk_every(1000)
      |> Enum.flat_map(fn clocks ->
        Repo.all(
          from m in Message,
            where: m.clock in ^clocks,
            select: {m.clock, m.table, m.row_id, m.column}
        )
      end)
      |> MapSet.new()

    Enum.reject(messages, &MapSet.member?(stored, key(&1)))
  end

  defp owned_by(messages, user_id) do
    rows = Enum.group_by(messages, &{&1.schema, &1.row_id})
    owners = existing_owners(rows)

    owned =
      for {{schema, id}, row_messages} <- rows,
          owner(schema, id, row_messages, rows, owners, user_id) == user_id,
          into: MapSet.new(),
          do: {schema, id}

    Enum.filter(messages, &MapSet.member?(owned, {&1.schema, &1.row_id}))
  end

  defp owner(schema, id, row_messages, rows, owners, user_id) do
    case {Map.fetch(owners, {schema, id}), Tables.parent(schema)} do
      {{:ok, owner}, _parent} ->
        owner

      {:error, nil} ->
        user_id

      {:error, {parent, key}} ->
        parent = {parent, latest_value(row_messages, key)}
        Map.get(owners, parent, if(Map.has_key?(rows, parent), do: user_id))
    end
  end

  defp latest_value(messages, field) do
    messages
    |> Enum.filter(&(&1.field == field))
    |> Enum.max_by(& &1.clock, fn -> %{decoded: nil} end)
    |> Map.fetch!(:decoded)
  end

  defp pointing_at_own(messages, user_id) do
    owners =
      messages
      |> Enum.flat_map(&target/1)
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
      |> Enum.reduce(%{}, fn {schema, ids}, owners ->
        Map.merge(owners, owners_of(schema, Enum.uniq(ids)))
      end)

    Enum.filter(messages, fn message ->
      case target(message) do
        [target] -> Map.get(owners, target, user_id) == user_id
        [] -> true
      end
    end)
  end

  defp target(%{decoded: nil}), do: []

  defp target(message) do
    case Tables.reference(message.schema, message.field) do
      nil -> []
      schema -> [{schema, message.decoded}]
    end
  end

  defp existing_owners(rows) do
    parents =
      for {{schema, _id}, row_messages} <- rows,
          {parent, key} <- List.wrap(Tables.parent(schema)),
          parent_id = latest_value(row_messages, key),
          not is_nil(parent_id),
          do: {parent, parent_id}

    (Map.keys(rows) ++ parents)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Enum.reduce(%{}, fn {schema, ids}, owners ->
      Map.merge(owners, owners_of(schema, Enum.uniq(ids)))
    end)
  end

  defp owners_of(schema, ids) do
    ids
    |> Enum.chunk_every(1000)
    |> Enum.flat_map(&Repo.all(owners_query(schema, &1)))
    |> Map.new(fn {id, owner} -> {{schema, id}, owner} end)
  end

  defp owners_query(schema, ids) do
    case Tables.parent(schema) do
      nil ->
        from r in schema, where: r.id in ^ids, select: {r.id, r.user_id}

      {parent, key} ->
        from r in schema,
          join: p in ^parent,
          on: p.id == field(r, ^key),
          where: r.id in ^ids,
          select: {r.id, p.user_id}
    end
  end

  defp winners(messages) do
    newest =
      messages
      |> Enum.group_by(&{&1.table, &1.row_id, &1.column})
      |> Enum.map(fn {_field, field_messages} -> Enum.max_by(field_messages, & &1.clock) end)

    clocks = field_clocks(newest)
    Enum.filter(newest, &newer?(&1, Map.get(clocks, {&1.table, &1.row_id, &1.column})))
  end

  defp newer?(_message, nil), do: true
  defp newer?(message, clock), do: message.clock > clock

  defp field_clocks(messages) do
    messages
    |> Enum.group_by(& &1.table, & &1.row_id)
    |> Enum.flat_map(fn {table, row_ids} ->
      row_ids
      |> Enum.uniq()
      |> Enum.chunk_every(1000)
      |> Enum.flat_map(fn ids ->
        Repo.all(
          from f in FieldClock,
            where: f.table == ^table and f.row_id in ^ids,
            select: {{f.table, f.row_id, f.column}, f.clock}
        )
      end)
    end)
    |> Map.new()
  end

  defp put_rows(winners, user_id) do
    rows = Enum.group_by(winners, &{&1.schema, &1.row_id})
    order = Map.new(Enum.with_index(Tables.schemas()))

    rows
    |> Enum.sort_by(fn {{schema, _id}, _messages} -> Map.fetch!(order, schema) end)
    |> Enum.map(fn {{schema, id}, messages} ->
      fields = Map.new(messages, &{&1.field, &1.decoded})
      {schema, id, fields, put_row(schema, id, fields, user_id)}
    end)
  end

  defp put_row(schema, id, fields, user_id) do
    fields = Map.merge(fields, derived(schema, fields))

    if Repo.exists?(from r in schema, where: r.id == ^id) do
      Repo.update_all(from(r in schema, where: r.id == ^id),
        set: Keyword.new(Map.put(fields, :updated_at, DateTime.utc_now()))
      )

      false
    else
      owner = if Tables.parent(schema), do: %{}, else: %{user_id: user_id}
      Repo.insert!(struct(schema, Map.merge(fields, Map.put(owner, :id, id))))
      true
    end
  end

  defp derived(schema, %{name: name}) when is_binary(name) do
    if :lookup_key in schema.__schema__(:fields),
      do: %{lookup_key: Names.lookup_key(name)},
      else: %{}
  end

  defp derived(_schema, _fields), do: %{}

  defp touched({schema, id, fields, created?}) when schema in [Payee, Category] do
    if created? or Enum.any?([:name, :category_group_id, :deleted_at], &Map.has_key?(fields, &1)),
      do: [{schema, id}],
      else: []
  end

  defp touched(_row), do: []

  defp settle(scope, applied, touched, refused, undone) do
    payees = for {Payee, id} <- touched, do: id
    categories = for {Category, id} <- touched, do: id

    referenced_payees =
      for m <- applied, m.decoded, Tables.reference(m.schema, m.field) == Payee, do: m.decoded

    deleted_categories =
      for %{schema: Category, field: field, row_id: id} <- applied,
          field in [:deleted_at, :successor_id],
          do: id

    accounts = for %{schema: Account, row_id: id} <- applied, uniq: true, do: id

    Sync.write(fn ->
      with :ok <- Authority.restore(refused, undone),
           :ok <- Ledger.put_missing_transfer_payees(scope, accounts),
           :ok <- Ledger.merge_duplicate_payees(scope, payees),
           :ok <- Ledger.follow_merged_payees(scope, referenced_payees),
           :ok <- Categories.merge_duplicate_categories(scope, categories),
           {:ok, nil} <- Categories.revive_stranded(scope),
           do: Categories.follow_deleted_categories(scope, deleted_categories)
    end)
  end
end
