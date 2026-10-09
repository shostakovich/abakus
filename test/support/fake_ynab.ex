defmodule Abakus.FakeYnab do
  @moduledoc """
  YNAB's API for tests, served by Bandit on a free port: `GET /v1/plans` and `GET /v1/plans/{id}` for the token
  `token/0`, answering like YNAB.
  """

  @behaviour Plug

  import Plug.Conn

  alias Abakus.YnabImport.Client

  @token "test-token"

  def token, do: @token

  @doc "Serves `plans` (exports by id) for the running test and points `Abakus.YnabImport.Client` at them."
  def start(plans) do
    server =
      ExUnit.Callbacks.start_supervised!(
        {Bandit, plug: {__MODULE__, plans}, ip: :loopback, port: 0, startup_log: false}
      )

    {:ok, {_ip, port}} = ThousandIsland.listener_info(server)
    previous = Application.get_env(:abakus, Client)
    Application.put_env(:abakus, Client, base_url: "http://127.0.0.1:#{port}/v1")

    ExUnit.Callbacks.on_exit(fn ->
      if previous,
        do: Application.put_env(:abakus, Client, previous),
        else: Application.delete_env(:abakus, Client)
    end)
  end

  @impl true
  def init(plans), do: plans

  @impl true
  def call(conn, plans) do
    case {get_req_header(conn, "authorization"), conn.path_info} do
      {["Bearer " <> @token], ["v1", "plans"]} ->
        respond(conn, 200, %{
          plans: Enum.map(plans, fn {id, plan} -> %{id: id, name: plan["name"]} end)
        })

      {["Bearer " <> @token], ["v1", "plans", id]} when is_map_key(plans, id) ->
        respond(conn, 200, %{plan: Map.fetch!(plans, id), server_knowledge: 1})

      {["Bearer " <> @token], _path} ->
        error(conn, 404, "not_found", "Resource not found")

      {_authorization, _path} ->
        error(conn, 401, "unauthorized", "Unauthorized")
    end
  end

  defp respond(conn, status, data), do: send_json(conn, status, %{data: data})

  defp error(conn, status, name, detail),
    do:
      send_json(conn, status, %{
        error: %{id: Integer.to_string(status), name: name, detail: detail}
      })

  defp send_json(conn, status, body) do
    conn |> put_resp_content_type("application/json") |> send_resp(status, JSON.encode!(body))
  end
end
