defmodule AbakusWeb.Api.Auth do
  @moduledoc "The API's plugs: a bearer token on every request, and the one plan in every path that names a plan."

  import Plug.Conn

  alias Abakus.ApiTokens
  alias AbakusWeb.Api

  def require_api_token(conn, _opts) do
    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         {:ok, api_token} <- ApiTokens.authenticate(token) do
      assign(conn, :api_token, api_token)
    else
      _ -> Api.send_error(conn, 401, "Token fehlt, ist ungültig oder widerrufen")
    end
  end

  def require_plan(%Plug.Conn{path_params: %{"plan_id" => plan_id}} = conn, _opts) do
    if plan_id == Api.plan_id(), do: conn, else: Api.send_not_found(conn)
  end

  def require_plan(conn, _opts), do: conn
end
