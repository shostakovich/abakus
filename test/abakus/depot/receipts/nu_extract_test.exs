defmodule Abakus.Depot.Receipts.NuExtractTest do
  use ExUnit.Case

  alias Abakus.Depot.Receipts.{ChatAPI, Fields, NuExtract}

  # Answers like a chat API and tells the test about the request.
  defmodule Stub do
    @behaviour Plug

    import Plug.Conn

    @impl true
    def init(opts), do: opts

    @impl true
    def call(conn, {test, response}) do
      {:ok, body, conn} = read_body(conn)
      send(test, {:request, conn.request_path, JSON.decode!(body)})
      send_resp(conn, 200, response)
    end
  end

  defp serve(response) do
    plug = {Stub, {self(), response}}
    server = {Bandit, plug: plug, ip: :loopback, port: 0, startup_log: false}
    pid = start_supervised!(server, id: make_ref())
    {:ok, {_ip, port}} = ThousandIsland.listener_info(pid)
    "http://127.0.0.1:#{port}/v1"
  end

  defp configure(config) do
    previous = Application.get_env(:abakus, ChatAPI)
    Application.put_env(:abakus, ChatAPI, config)

    on_exit(fn ->
      if previous,
        do: Application.put_env(:abakus, ChatAPI, previous),
        else: Application.delete_env(:abakus, ChatAPI)
    end)
  end

  test "asks with a template of the fields and the text, and answers by the schema" do
    content = ~s({"kind": "dividend", "date": "2026-03-10T00:00:00", "shares": "STK 12,000"})
    response = JSON.encode!(%{choices: [%{message: %{content: content}}]})
    configure(url: serve(response), model: "nuextract3", prelude: "Lies den Beleg.")

    assert {:ok, answer} = NuExtract.answer("ignored", [{:user, "Beleg"}], Fields.json_schema())

    assert {:ok, %Fields{kind: :dividend, date: ~D[2026-03-10], isin: nil} = fields} =
             Fields.from_answer(answer, :german)

    assert Decimal.equal?(fields.shares, 12)

    assert_received {:request, "/v1/chat/completions", body}
    assert body["reasoning_effort"] == "none"
    assert [%{"role" => "user", "content" => prompt}] = body["messages"]
    assert prompt =~ ~r/^Lies den Beleg.\n# Template:\n\{"kind":\["purchase",/
    assert prompt =~ ~s("date":"date-time","isin":"verbatim-string")
    assert String.ends_with?(prompt, "\n# Context:\nBeleg")
  end

  test "cannot continue a chat" do
    assert NuExtract.answer("", [{:user, "Beleg"}, {:assistant, "{}"}, {:user, "Prüfe"}], %{}) ==
             {:error, :no_chat}
  end
end
