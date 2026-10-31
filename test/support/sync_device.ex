defmodule Abakus.SyncDevice do
  @moduledoc """
  A simulated app for sync tests: it keeps every field it has heard of with its clock, edits fields offline as
  messages in its outbox, pushes them and pulls the messages the server has after its cursor, the newest clock of a
  field winning, as `sync/PROTOCOL.md` asks of every writer.
  """

  import Ecto.Query, only: [from: 2]
  import ExUnit.Assertions

  alias Abakus.{Repo, Sync}
  alias Abakus.Sync.{Clock, Message, Tables}
  alias Abakus.Users.Scope

  defstruct [:id, :scope, clock: nil, fields: %{}, outbox: [], cursor: 0]

  @doc "A device that has pulled everything the server has so far."
  def new(scope, id), do: pull(%__MODULE__{id: id, scope: scope})

  @doc "Changes fields of a row at the wall time `at`, all with one clock."
  def edit(device, table, row_id, fields, %DateTime{} = at) do
    clock = device.clock |> Clock.tick(DateTime.to_unix(at, :millisecond), device.id)

    messages =
      for {column, value} <- fields do
        %{
          "table" => table,
          "row_id" => row_id,
          "column" => to_string(column),
          "value" => value,
          "clock" => Clock.to_string(clock)
        }
      end

    %{merge(device, messages) | outbox: device.outbox ++ messages}
  end

  @doc "Sends the outbox."
  def push(device) do
    assert {:ok, _stored} = Sync.apply_messages(device.scope, device.id, device.outbox)
    %{device | outbox: []}
  end

  @doc "Takes the messages of other devices after the cursor."
  def pull(device) do
    messages =
      for m <- messages_after(device.scope, device.cursor, device.id) do
        %{
          "table" => m.table,
          "row_id" => m.row_id,
          "column" => m.column,
          "value" => JSON.decode!(m.value),
          "clock" => m.clock
        }
      end

    %{merge(device, messages) | cursor: Sync.cursor(device.scope)}
  end

  def sync(device), do: device |> push() |> pull()

  @doc "The user's messages after `cursor` that another device than `device` wrote, in order of arrival."
  def messages_after(%Scope{user: %{id: user_id}}, cursor, device) do
    Repo.all(
      from m in Message,
        where: m.user_id == ^user_id and m.id > ^cursor and m.device != ^device,
        order_by: m.id
    )
  end

  @doc "A row's fields as the device has them, by column name."
  def row(device, table, row_id) do
    for {{^table, ^row_id, column}, {value, _clock}} <- device.fields,
        into: %{},
        do: {column, value}
  end

  @doc "The rows of a table the device knows, by id."
  def rows(device, table) do
    for {{^table, row_id, _column}, _value} <- device.fields,
        uniq: true,
        into: %{},
        do: {row_id, row(device, table, row_id)}
  end

  @doc "Asserts that the device has every synced field of the server's row as the server has it."
  def assert_converged(device, schema, row_id) do
    row = Repo.get!(schema, row_id)
    known = row(device, Tables.table(schema), row_id)

    for column <- Tables.columns(schema) do
      assert Map.get(known, Atom.to_string(column)) == Tables.encode(Map.fetch!(row, column)),
             "#{Tables.table(schema)}.#{column} of #{row_id} differs on #{device.id}"
    end
  end

  defp merge(device, messages) do
    Enum.reduce(messages, device, fn message, device ->
      %{"clock" => text, "value" => value} = message
      {:ok, clock} = Clock.parse(text)
      key = {message["table"], message["row_id"], message["column"]}

      fields =
        case device.fields do
          %{^key => {_value, newer}} when newer >= text -> device.fields
          fields -> Map.put(fields, key, {value, text})
        end

      %{device | fields: fields, clock: later(device.clock, clock)}
    end)
  end

  defp later(nil, clock), do: clock

  defp later(own, clock),
    do: if({clock.millis, clock.counter} > {own.millis, own.counter}, do: clock, else: own)
end
