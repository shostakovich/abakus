defmodule Abakus.HTTPTest do
  use ExUnit.Case, async: true

  alias Abakus.HTTP

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

    def call(conn, {:body, body}), do: send_resp(conn, 200, body)

    def call(conn, {:chunks, chunks}) do
      conn = send_chunked(conn, 200)

      Enum.reduce(chunks, conn, fn chunk, conn ->
        {:ok, conn} = chunk(conn, chunk)
        conn
      end)
    end

    def call(conn, {:status, status}), do: send_resp(conn, status, "nope")

    def call(conn, {:record, test}) do
      {:ok, body, conn} = read_body(conn)
      send(test, {:request, conn.method, conn.query_string, conn.req_headers, body})
      conn |> put_resp_header("retry-after", "60") |> send_resp(201, "recorded")
    end
  end

  defp serve(opts) do
    server = {Bandit, plug: {Stub, opts}, ip: :loopback, port: 0, startup_log: false}
    pid = start_supervised!(server, id: make_ref())
    {:ok, {_ip, port}} = ThousandIsland.listener_info(pid)
    "http://127.0.0.1:#{port}/"
  end

  test "gets the status and body with query parameters, headers and a default user agent" do
    url = serve({:record, self()})

    assert HTTP.get(url, params: [q: "a b", n: 1], headers: [{"x-api-key", "k"}]) ==
             {:ok, 201, "recorded"}

    assert_received {:request, "GET", "q=a+b&n=1", headers, ""}
    assert {"x-api-key", "k"} in headers
    assert {"user-agent", "Mozilla/5.0 (compatible; Abakus)"} in headers

    assert HTTP.get(serve({:status, 503})) == {:ok, 503, "nope"}
  end

  test "lets the caller set the user agent" do
    assert {:ok, 201, _body} =
             HTTP.get(serve({:record, self()}), headers: [{"User-Agent", "abakus/1.0"}])

    assert_received {:request, "GET", _query, headers, _body}
    assert Enum.filter(headers, &(elem(&1, 0) == "user-agent")) == [{"user-agent", "abakus/1.0"}]
  end

  test "sends other methods with a JSON body and returns the response headers" do
    url = serve({:record, self()})

    assert {:ok, 201, headers, "recorded"} =
             HTTP.request(:post, url, headers: [{"authorization", "Bearer t"}], json: %{n: [1]})

    assert {"retry-after", "60"} in headers
    assert_received {:request, "POST", _query, request_headers, ~s({"n":[1]})}
    assert {"authorization", "Bearer t"} in request_headers
    assert {"content-type", "application/json"} in request_headers

    assert {:ok, 201, "recorded"} = HTTP.post(url, json: [])
    assert_received {:request, "POST", _query, _headers, "[]"}
    assert {:ok, 201, _headers, "recorded"} = HTTP.request(:patch, url, json: [])
    assert_received {:request, "PATCH", _query, _headers, "[]"}
    assert {:ok, 201, _headers, "recorded"} = HTTP.request(:delete, url)
    assert_received {:request, "DELETE", _query, _headers, ""}
  end

  test "does not follow a redirect unless asked to" do
    url = serve({:redirect, serve({:record, self()})})

    assert {:ok, 302, _body} = HTTP.get(url)
    assert {:ok, 302, _body} = HTTP.post(url, json: %{})
    refute_received {:request, _method, _query, _headers, _body}

    assert HTTP.get(url, follow_redirects: true) == {:ok, 201, "recorded"}
  end

  test "refuses a redirect of a request with headers, which may carry an API key" do
    url = serve({:redirect, serve({:record, self()})})

    assert {:ok, 302, _body} =
             HTTP.get(url, headers: [{"x-api-key", "secret"}], follow_redirects: true)

    refute_received {:request, _method, _query, _headers, _body}
  end

  test "enforces the body cap" do
    assert HTTP.get(serve({:body, String.duplicate("x", 100)}), max_body: 100) ==
             {:ok, 200, String.duplicate("x", 100)}

    assert HTTP.get(serve({:body, String.duplicate("x", 101)}), max_body: 100) ==
             {:error, :too_large}

    chunks = List.duplicate(String.duplicate("x", 60), 3)
    assert HTTP.get(serve({:chunks, chunks}), max_body: 100) == {:error, :too_large}
  end

  test "hits the deadline for the whole response" do
    assert HTTP.get(serve({:sleep, 500}), timeout: 50) == {:error, :timeout}
  end

  test "never returns a reason that contains the request" do
    result =
      HTTP.get("http://127.0.0.1:1/",
        params: [token: "secret"],
        headers: [{"authorization", "Bearer secret"}]
      )

    assert result == {:error, :unreachable}
    assert HTTP.post("https://localhost:1/secret", json: %{}) == {:error, :unreachable}
  end
end
