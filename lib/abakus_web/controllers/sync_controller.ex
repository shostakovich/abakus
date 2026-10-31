defmodule AbakusWeb.SyncController do
  @moduledoc """
  The sync API for a signed-in device (`sync/PROTOCOL.md`, `AbakusWeb.DeviceAuth`). Sync applies the device's
  messages and answers with the other writers' messages after its cursor; with nothing to send or receive it waits up
  to 25 seconds for a write to the budget, woken over PubSub, and is refused once woken if the device was signed out
  meanwhile. Snapshot answers with every synced row for a newly signed-in device.
  """
  use AbakusWeb, :controller

  alias Abakus.{Devices, LocalTime, Sync}
  alias AbakusWeb.DeviceAuth

  @limit 1000

  def sync(conn, params) do
    %{current_scope: scope, current_device: device} = conn.assigns

    with {:ok, cursor} <- cursor(params["cursor"]),
         {:ok, messages} <- messages(params["messages"]),
         {:ok, _stored} <- Sync.apply_messages(scope, device.id, messages),
         :ok <- Devices.synced(device),
         {messages, cursor, more?} <- pull(scope, device, cursor, messages == []) do
      json(conn, %{cursor: cursor, messages: Enum.map(messages, &message/1), more: more?})
    else
      :signed_out -> DeviceAuth.refuse_token(conn)
      {:error, reason} -> refuse(conn, reason)
    end
  end

  def snapshot(conn, _params) do
    %{current_scope: scope, current_device: device} = conn.assigns
    Devices.synced(device)
    json(conn, Sync.snapshot(scope))
  end

  defp cursor(nil), do: {:ok, 0}
  defp cursor(cursor) when is_integer(cursor) and cursor >= 0, do: {:ok, cursor}
  defp cursor(_cursor), do: {:error, :invalid_cursor}

  defp messages(nil), do: {:ok, []}
  defp messages(messages) when is_list(messages), do: {:ok, messages}
  defp messages(_messages), do: {:error, :invalid_messages}

  defp pull(scope, device, cursor, false = _wait?),
    do: Sync.pull(scope, cursor, device.id, @limit)

  defp pull(scope, device, cursor, true = _wait?) do
    Sync.subscribe_messages(scope)

    deadline =
      System.monotonic_time(:millisecond) + Application.get_env(:abakus, :sync_wait, 25_000)

    try do
      wait(scope, device, cursor, deadline)
    after
      Sync.unsubscribe_messages(scope)
      flush_written()
    end
  end

  defp wait(scope, device, cursor, deadline) do
    case Sync.pull(scope, cursor, device.id, @limit) do
      {[], cursor, false} ->
        id = device.id

        receive do
          {:written, writer} when writer != id -> woken(scope, device, cursor, deadline)
        after
          max(deadline - System.monotonic_time(:millisecond), 0) -> {[], cursor, false}
        end

      pulled ->
        pulled
    end
  end

  defp woken(scope, device, cursor, deadline) do
    if Devices.signed_in?(device), do: wait(scope, device, cursor, deadline), else: :signed_out
  end

  # The connection's process serves its next request too.
  defp flush_written do
    receive do
      {:written, _writer} -> flush_written()
    after
      0 -> :ok
    end
  end

  defp message(message) do
    %{
      table: message.table,
      row_id: message.row_id,
      column: message.column,
      value: JSON.decode!(message.value),
      clock: message.clock
    }
  end

  defp refuse(conn, {:clock_ahead, clock}) do
    conn
    |> put_status(:bad_request)
    |> json(%{
      error: "clock_ahead",
      clock: clock,
      server_time: DateTime.to_iso8601(LocalTime.utc_now()),
      message: "Die Uhr dieses Geräts geht vor. Bitte stelle sie richtig."
    })
  end

  defp refuse(conn, reason) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "invalid_request", detail: inspect(reason)})
  end
end
