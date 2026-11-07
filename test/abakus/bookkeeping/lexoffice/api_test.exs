defmodule Abakus.Bookkeeping.Lexoffice.APITest do
  use ExUnit.Case, async: false

  alias Abakus.Bookkeeping.Lexoffice.API

  # Lexoffice behind the key „secret“: each path's answers in turn from an Agent, the last one repeating.
  defmodule Stub do
    @behaviour Plug

    import Plug.Conn

    @impl true
    def init(state), do: state

    @impl true
    def call(conn, state) do
      conn = fetch_query_params(conn)
      path = Enum.join(conn.path_info, "/")

      Agent.update(
        state,
        &%{&1 | requests: &1.requests ++ [{path, conn.query_params, accept(conn)}]}
      )

      if get_req_header(conn, "authorization") == ["Bearer secret"],
        do: answer(conn, Agent.get_and_update(state, &next(&1, path))),
        else: send_resp(conn, 401, ~s({"message": "Unauthorized"}))
    end

    defp accept(conn), do: conn |> get_req_header("accept") |> List.first()

    defp next(state, path) do
      case state.answers[path] || [{404, "{}"}] do
        [answer] -> {answer, state}
        [answer | rest] -> {answer, put_in(state.answers[path], rest)}
      end
    end

    defp answer(conn, {status, body}), do: send_resp(conn, status, body)
  end

  setup do
    state =
      start_supervised!(
        {Agent,
         fn ->
           %{
             answers: %{
               "v1/contacts" => [{200, ~s({"content": [], "last": true})}],
               "v1/payments/p1" => [{406, ~s({"message": "No payment information"})}],
               "v1/invoices/busy" => [{429, "{}"}, {200, ~s({"id": "busy"})}],
               "v1/invoices/always-busy" => [{429, "{}"}],
               "v1/files/f1" => [{200, "%PDF-1.4 original"}]
             },
             requests: []
           }
         end}
      )

    server = {Bandit, plug: {Stub, state}, ip: :loopback, port: 0, startup_log: false}
    {:ok, {_ip, port}} = server |> start_supervised!() |> ThousandIsland.listener_info()
    configure(base_url: "http://127.0.0.1:#{port}/v1/")
    %{state: state}
  end

  defp configure(opts) do
    previous = Application.get_env(:abakus, API, [])
    Application.put_env(:abakus, API, Keyword.merge(previous, opts))
    on_exit(fn -> Application.put_env(:abakus, API, previous) end)
  end

  defp key, do: fn -> "secret" end

  defp requests(state), do: Agent.get(state, & &1.requests)

  test "gets the JSON of a path with the key as bearer token and the query", %{state: state} do
    assert API.get(key(), "contacts", customer: true, page: 0) ==
             {:ok, %{"content" => [], "last" => true}}

    assert requests(state) ==
             [{"v1/contacts", %{"customer" => "true", "page" => "0"}, "application/json"}]
  end

  test "downloads a file by its id" do
    assert API.download(key(), "f1") == {:ok, "%PDF-1.4 original"}
  end

  test "a refused key is unauthorized, a voucher without payments and a missing path not found" do
    assert API.get(fn -> "wrong" end, "contacts", []) == {:error, :unauthorized}
    assert API.get(key(), "payments/p1", []) == {:error, :not_found}
    assert API.get(key(), "invoices/missing", []) == {:error, :not_found}
  end

  test "asks again after a 429, and gives up after three more", %{state: state} do
    assert API.get(key(), "invoices/busy", []) == {:ok, %{"id" => "busy"}}
    assert API.get(key(), "invoices/always-busy", []) == {:error, :rate_limited}
    assert length(requests(state)) == 2 + 4
  end

  test "keeps requests half a second apart" do
    configure(interval: 500)
    started = System.monotonic_time(:millisecond)

    for _request <- 1..3, do: API.get(key(), "contacts", [])

    assert System.monotonic_time(:millisecond) - started >= 1000
  end

  test "an id goes into the path as one segment", %{state: state} do
    API.download(key(), "../invoices/x")
    assert [{"v1/files/..%2Finvoices%2Fx", _params, "*/*"}] = requests(state)
  end
end
