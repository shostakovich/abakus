defmodule Abakus.Sync do
  @moduledoc """
  The one write path of the synced tables (ADR 0024, `sync/PROTOCOL.md`).

  A write of the Ledger or the budget runs in `write/1` and changes rows only through `insert/2`, `update/2`,
  `update_all/3` and `delete_all/2`, which keep each row's fields before it changes. When the write is done, still
  in its database transaction, every changed field becomes a message with the server's clock, one clock for the
  whole write, so a transfer's sides or a split's parts win or lose together. Rows are never removed: deleting
  sets `deleted_at`.

  `apply_messages/3` takes another device's messages in one database transaction (`Abakus.Sync.Incoming`) and
  tells the owner's LiveViews over PubSub (`subscribe/1`); `rewrite/3` writes fields a device may not change again,
  unchanged. `pull/4` reads the messages after a cursor, and a device's waiting sync request
  hears of new ones once they have committed, the server's and the devices' (`subscribe_messages/1`).
  """

  import Ecto.Query, only: [from: 2]

  alias Abakus.{LocalTime, Repo}
  alias Abakus.Sync.{Clock, FieldClock, Incoming, Message, Tables}
  alias Abakus.Users.Scope

  @server "server"
  @protocol_versions [1]
  @tracked {__MODULE__, :tracked}

  @doc "The versions of the sync API's protocol the server speaks."
  def protocol_versions, do: @protocol_versions

  @doc """
  Runs `fun` (returning `{:ok, result}` or `{:error, reason}`) in a database transaction and records its changes as
  messages before the transaction ends; a write inside another one is part of it.
  """
  def write(fun) when is_function(fun, 0) do
    if tracking?(), do: Repo.transact(fun), else: Repo.transact(fn -> tracked(fun) end)
  end

  defp tracked(fun) do
    Process.put(@tracked, %{rows: %{}, parents: MapSet.new(), rewrites: %{}})

    with {:ok, result} <- fun.() do
      record(Process.get(@tracked))
      {:ok, result}
    end
  after
    Process.delete(@tracked)
  end

  defp tracking?, do: Process.get(@tracked) != nil

  @doc "`Repo.insert/2` as part of a write."
  def insert(changeset_or_struct, opts \\ []) do
    within(fn ->
      schema = schema_of(changeset_or_struct)
      if id = given_id(changeset_or_struct), do: track(schema, [id])

      with {:ok, row} <- Repo.insert(changeset_or_struct, opts) do
        remember_new(schema, row.id)
        watch_parts(schema, [row.id])
        {:ok, row}
      end
    end)
  end

  @doc "`Repo.insert!/2` as part of a write."
  def insert!(changeset_or_struct, opts \\ []),
    do: changeset_or_struct |> insert(opts) |> unwrap!(:insert)

  @doc "`Repo.update/2` as part of a write."
  def update(%Ecto.Changeset{data: %schema{id: id}} = changeset, opts \\ []) do
    within(fn ->
      track(schema, [id])
      Repo.update(changeset, opts)
    end)
  end

  @doc "`Repo.update!/2` as part of a write."
  def update!(changeset, opts \\ []), do: changeset |> update(opts) |> unwrap!(:update)

  @doc "`Repo.update_all/3` as part of a write."
  def update_all(queryable, updates, opts \\ []) do
    within(fn ->
      query = Ecto.Queryable.to_query(queryable)
      remember(Repo.all(query))
      Repo.update_all(query, updates, opts)
    end)
  end

  @doc "Deletes the rows that are not deleted yet as tombstones, setting `deleted_at` and the `also` fields."
  def delete_all(queryable, also \\ []) do
    now = DateTime.utc_now()

    update_all(from(r in queryable, where: is_nil(r.deleted_at)),
      set: [deleted_at: now, updated_at: now] ++ also
    )
  end

  @doc "Writes the fields `columns` of a row again as they are, so that a device that changed them converges back."
  def rewrite(schema, id, columns) do
    within(fn ->
      remember(Repo.all(from r in schema, where: r.id == ^id))
      columns = MapSet.new(columns)

      update_state(
        :rewrites,
        &Map.update(&1, {schema, id}, columns, fn s -> MapSet.union(s, columns) end)
      )

      :ok
    end)
  end

  defp within(fun) do
    if tracking?() do
      fun.()
    else
      {:ok, result} = write(fn -> {:ok, fun.()} end)
      result
    end
  end

  defp unwrap!({:ok, row}, _action), do: row

  defp unwrap!({:error, changeset}, action),
    do: raise(Ecto.InvalidChangesetError, action: action, changeset: changeset)

  defp schema_of(%Ecto.Changeset{data: %schema{}}), do: schema
  defp schema_of(%schema{}), do: schema

  defp given_id(%Ecto.Changeset{} = changeset), do: Ecto.Changeset.get_field(changeset, :id)
  defp given_id(%{id: id}), do: id

  defp track(schema, ids) do
    remember(Repo.all(from r in schema, where: r.id in ^ids))
    for id <- ids, do: remember_new(schema, id)

    for {child, key} <- Tables.children(schema),
        do: remember(Repo.all(from c in child, where: field(c, ^key) in ^ids))

    watch_parts(schema, ids)
  end

  defp watch_parts(schema, ids) do
    if Tables.children(schema) != [],
      do: update_state(:parents, &MapSet.union(&1, MapSet.new(ids, fn id -> {schema, id} end)))
  end

  defp remember(rows) do
    update_state(:rows, fn tracked ->
      Enum.reduce(rows, tracked, fn %schema{id: id} = row, tracked ->
        Map.put_new(tracked, {schema, id}, Tables.values(row))
      end)
    end)
  end

  defp remember_new(schema, id),
    do: update_state(:rows, &Map.put_new(&1, {schema, id}, nil))

  defp update_state(key, fun),
    do: Process.put(@tracked, Map.update!(Process.get(@tracked), key, fun))

  defp record(%{rows: rows, parents: parents, rewrites: rewrites}) do
    rows = Enum.reduce(parents, rows, &put_new_children/2)

    changes =
      rows
      |> Enum.group_by(fn {{schema, _id}, _before} -> schema end)
      |> Enum.flat_map(fn {schema, entries} -> changes(schema, entries, rewrites) end)

    if changes != [], do: store(changes, next_clock())
  end

  defp put_new_children({schema, id}, rows) do
    for {child, key} <- Tables.children(schema),
        child_id <- Repo.all(from c in child, where: field(c, ^key) == ^id, select: c.id),
        reduce: rows,
        do: (rows -> Map.put_new(rows, {child, child_id}, nil))
  end

  defp changes(schema, entries, rewrites) do
    ids = Enum.map(entries, fn {{_schema, id}, _before} -> id end)

    after_rows =
      ids
      |> in_chunks(fn ids -> Repo.all(from r in schema, where: r.id in ^ids) end)
      |> Map.new(&{&1.id, &1})

    owners = owners(schema, Map.values(after_rows))

    for {{_schema, id}, before} <- entries,
        row = Map.get(after_rows, id),
        {column, value} <-
          diff(schema, id, before, row, Map.get(rewrites, {schema, id}, MapSet.new())) do
      %{
        user_id: Map.fetch!(owners, id),
        table: Tables.table(schema),
        row_id: id,
        column: column,
        value: value
      }
    end
  end

  defp diff(_schema, _id, nil = _before, nil = _row, _rewritten), do: []

  defp diff(schema, id, _before, nil, _rewritten),
    do:
      raise(
        ArgumentError,
        "#{Tables.table(schema)} #{id} was removed; synced rows are never removed"
      )

  defp diff(_schema, _id, before, row, rewritten) do
    for {column, value} <- Tables.values(row),
        changed?(before, column, value) or MapSet.member?(rewritten, column),
        do: {Atom.to_string(column), value}
  end

  defp changed?(nil = _before, _column, value), do: not is_nil(value)
  defp changed?(before, column, value), do: Map.fetch!(before, column) != value

  defp owners(schema, rows) do
    case Tables.parent(schema) do
      nil ->
        Map.new(rows, &{&1.id, &1.user_id})

      {parent, key} ->
        parent_ids = rows |> Enum.map(&Map.fetch!(&1, key)) |> Enum.uniq()

        users =
          parent_ids
          |> in_chunks(fn ids ->
            Repo.all(from p in parent, where: p.id in ^ids, select: {p.id, p.user_id})
          end)
          |> Map.new()

        Map.new(rows, &{&1.id, Map.fetch!(users, Map.fetch!(&1, key))})
    end
  end

  defp next_clock do
    last =
      case Repo.one(from m in Message, select: max(m.clock)) do
        nil -> nil
        text -> elem(Clock.parse(text), 1)
      end

    Clock.tick(last, DateTime.to_unix(LocalTime.utc_now(), :millisecond), @server)
  end

  defp store(changes, clock) do
    messages =
      Enum.map(changes, &Map.merge(&1, %{clock: Clock.to_string(clock), device: @server}))

    store_messages(messages)
    put_field_clocks(messages)

    for user_id <- messages |> Enum.map(& &1.user_id) |> Enum.uniq(),
        do: Repo.after_commit({__MODULE__, user_id}, fn -> tell_written(user_id, @server) end)
  end

  @doc false
  def store_messages(messages) do
    now = DateTime.utc_now()

    rows =
      Enum.map(messages, fn message ->
        message
        |> Map.take([:user_id, :table, :row_id, :column, :clock, :device])
        |> Map.merge(%{value: JSON.encode!(message.value), inserted_at: now})
      end)

    for chunk <- Enum.chunk_every(rows, 1000), do: Repo.insert_all(Message, chunk)
  end

  @doc false
  def put_field_clocks(messages) do
    rows = Enum.map(messages, &Map.take(&1, [:table, :row_id, :column, :clock]))

    for chunk <- Enum.chunk_every(rows, 1000) do
      Repo.insert_all(FieldClock, chunk,
        on_conflict: {:replace, [:clock]},
        conflict_target: [:table, :row_id, :column]
      )
    end
  end

  @doc """
  Applies a device's messages for the scope's user (`Abakus.Sync.Incoming`), in one database transaction, and tells
  the user's LiveViews and waiting devices. Returns `{:ok, applied}` with the number of messages stored, or `{:error, reason}`.
  """
  def apply_messages(%Scope{user: %{id: user_id}} = scope, device, messages) do
    with {:ok, stored} <- Incoming.apply(scope, device, messages) do
      if stored > 0 do
        Phoenix.PubSub.broadcast(Abakus.PubSub, topic(user_id), {:synced, device})
        tell_written(user_id, device)
      end

      {:ok, stored}
    end
  end

  @doc "Subscribes to `{:synced, device}`, sent when another device's messages changed the user's budget."
  def subscribe(%Scope{user: %{id: id}}), do: Phoenix.PubSub.subscribe(Abakus.PubSub, topic(id))

  @doc "Subscribes to `{:written, writer}`, sent when the server or a device stored messages of the user."
  def subscribe_messages(%Scope{user: %{id: id}}),
    do: Phoenix.PubSub.subscribe(Abakus.PubSub, written_topic(id))

  def unsubscribe_messages(%Scope{user: %{id: id}}),
    do: Phoenix.PubSub.unsubscribe(Abakus.PubSub, written_topic(id))

  defp tell_written(user_id, writer),
    do: Phoenix.PubSub.broadcast(Abakus.PubSub, written_topic(user_id), {:written, writer})

  defp topic(user_id), do: "sync:#{user_id}"
  defp written_topic(user_id), do: "sync:#{user_id}:written"

  @doc """
  The user's messages after `cursor` that another device than `device` wrote, reading at most `limit` messages of
  all devices: `{messages, cursor, more?}`, with the cursor of the last message read.
  """
  def pull(%Scope{user: %{id: user_id}}, cursor, device, limit) do
    read =
      Repo.all(
        from m in Message,
          where: m.user_id == ^user_id and m.id > ^cursor,
          order_by: m.id,
          limit: ^(limit + 1)
      )

    {read, rest} = Enum.split(read, limit)
    last = List.last(read)

    {Enum.reject(read, &(&1.device == device)), if(last, do: last.id, else: cursor), rest != []}
  end

  @doc "Every synced row of the user with its fields' clocks, and the cursor (`Abakus.Sync.Snapshot`)."
  defdelegate snapshot(scope), to: Abakus.Sync.Snapshot, as: :take

  @doc "The number of the user's newest message, 0 for none."
  def cursor(%Scope{user: %{id: user_id}}),
    do: Repo.one(from m in Message, where: m.user_id == ^user_id, select: coalesce(max(m.id), 0))

  defp in_chunks(values, query), do: values |> Enum.chunk_every(1000) |> Enum.flat_map(query)
end
