defmodule Abakus.Depot.MarketData.HTTPTest do
  use ExUnit.Case, async: true

  alias Abakus.Depot.MarketData.HTTP

  # Redirects to `to`, or tells the test about the request it got.
  defmodule Stub do
    @behaviour Plug

    import Plug.Conn

    @impl true
    def init(opts), do: opts

    @impl true
    def call(conn, {:redirect, to}),
      do: conn |> put_resp_header("location", to) |> send_resp(302, "")

    def call(conn, {:sleep, ms}) do
      Process.sleep(ms)
      send_resp(conn, 200, "late")
    end

    def call(conn, {:record, test}) do
      {:ok, body, conn} = read_body(conn)
      send(test, {:request, conn.method, conn.req_headers, body})
      send_resp(conn, 200, "redirected")
    end
  end

  defp serve(opts) do
    server = {Bandit, plug: {Stub, opts}, ip: :loopback, port: 0, startup_log: false}
    pid = start_supervised!(server, id: make_ref())
    {:ok, {_ip, port}} = ThousandIsland.listener_info(pid)
    "http://127.0.0.1:#{port}/"
  end

  test "does not follow a redirect of a request with headers, which may carry an API key" do
    url = serve({:redirect, serve({:record, self()})})

    assert {:ok, 302, _body} = HTTP.get(url, [], [{"x-api-key", "secret"}])
    refute_received {:request, _method, _headers, _body}
  end

  test "follows a redirect of a request without headers" do
    url = serve({:redirect, serve({:record, self()})})

    assert HTTP.get(url, []) == {:ok, 200, "redirected"}
  end

  test "posts JSON" do
    url = serve({:record, self()})

    assert HTTP.post_json(url, %{model: "qwen", n: 1}, [{"authorization", "Bearer key"}]) ==
             {:ok, 200, "redirected"}

    assert_received {:request, "POST", headers, body}
    assert {"content-type", "application/json"} in headers
    assert {"authorization", "Bearer key"} in headers
    assert JSON.decode!(body) == %{"model" => "qwen", "n" => 1}
  end

  test "tells a response that does not come in time from no response at all" do
    assert HTTP.post_json(serve({:sleep, 500}), %{}, [], timeout: 50) == {:error, :timeout}
    assert HTTP.get("http://127.0.0.1:1/", []) == {:error, :unreachable}
  end

  test "does not follow a redirect of a POST" do
    url = serve({:redirect, serve({:record, self()})})

    assert {:ok, 302, _body} = HTTP.post_json(url, %{})
    refute_received {:request, _method, _headers, _body}
  end
end
