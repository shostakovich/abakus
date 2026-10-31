defmodule AbakusWeb.DeviceAuth do
  @moduledoc """
  Plug for the sync API (`sync/PROTOCOL.md`): the request's bearer access token names the budget owner and the device
  (`Abakus.Devices`), assigned as `current_scope` and `current_device`, and its `Abakus-Protocol` header a version
  the server still speaks; an app that sends another is asked to update.
  """
  @behaviour Plug

  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]

  alias Abakus.{Devices, Sync}

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] -> authenticate(conn, Devices.authenticate(token))
      _none -> refuse(conn, ~s(Bearer realm="Abakus"))
    end
  end

  defp authenticate(conn, {:ok, scope, device}) do
    conn
    |> assign(:current_scope, scope)
    |> assign(:current_device, device)
    |> check_protocol()
  end

  defp authenticate(conn, :error), do: refuse_token(conn)

  @doc "Answers 401 with `invalid_token`, so the app refreshes its tokens or signs in again."
  def refuse_token(conn), do: refuse(conn, ~s(Bearer realm="Abakus", error="invalid_token"))

  defp refuse(conn, challenge) do
    conn
    |> put_resp_header("www-authenticate", challenge)
    |> put_status(:unauthorized)
    |> json(%{error: "invalid_token"})
    |> halt()
  end

  defp check_protocol(conn) do
    versions = Enum.map(Sync.protocol_versions(), &Integer.to_string/1)

    if get_req_header(conn, "abakus-protocol") in Enum.map(versions, &[&1]) do
      conn
    else
      conn
      |> put_status(:bad_request)
      |> json(%{
        error: "unsupported_protocol",
        supported: Sync.protocol_versions(),
        message: "Diese Version der App kann nicht mehr synchronisieren. Bitte aktualisiere sie."
      })
      |> halt()
    end
  end
end
