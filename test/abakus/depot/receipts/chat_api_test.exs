defmodule Abakus.Depot.Receipts.ChatAPITest do
  use ExUnit.Case

  alias Abakus.Depot.Receipts.ChatAPI

  # Answers like an OpenAI-compatible chat API and tells the test about the request.
  defmodule Stub do
    @behaviour Plug

    import Plug.Conn

    @impl true
    def init(opts), do: opts

    @impl true
    def call(conn, {test, status, response}) do
      {:ok, body, conn} = read_body(conn)
      send(test, {:request, conn.request_path, conn.req_headers, JSON.decode!(body)})
      send_resp(conn, status, response)
    end
  end

  defp serve(status, response) do
    plug = {Stub, {self(), status, response}}
    server = {Bandit, plug: plug, ip: :loopback, port: 0, startup_log: false}
    pid = start_supervised!(server, id: make_ref())
    {:ok, {_ip, port}} = ThousandIsland.listener_info(pid)
    "http://127.0.0.1:#{port}/v1/"
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

  defp completion(content), do: JSON.encode!(%{choices: [%{message: %{content: content}}]})

  test "is available with URL and model" do
    configure(url: "http://localhost:11434/v1", model: nil)
    refute ChatAPI.available?()
    assert ChatAPI.name() == nil

    configure(url: "http://ollama:11434/v1", model: "qwen3")
    assert ChatAPI.available?()
    assert ChatAPI.name() == "qwen3 auf ollama"
  end

  test "asks the chat API for JSON by the schema and returns its content" do
    configure(url: serve(200, completion(~s({"kind":"other"}))), model: "qwen3", api_key: "key")

    assert ChatAPI.answer("Lies den Beleg.", [{:user, "Wertpapierabrechnung"}], %{
             type: "object"
           }) ==
             {:ok, ~s({"kind":"other"})}

    assert_received {:request, "/v1/chat/completions", headers, body}
    assert {"authorization", "Bearer key"} in headers
    assert body["model"] == "qwen3"
    assert body["temperature"] == 0

    assert body["messages"] == [
             %{"role" => "system", "content" => "Lies den Beleg."},
             %{"role" => "user", "content" => "Wertpapierabrechnung"}
           ]

    assert body["response_format"]["type"] == "json_schema"
    assert body["response_format"]["json_schema"]["schema"] == %{"type" => "object"}
  end

  test "continues the chat with the model's answer and the correction asked for" do
    configure(url: serve(200, completion("{}")), model: "qwen3")

    messages = [
      {:user, "Beleg"},
      {:assistant, ~s({"kind":"other"})},
      {:user, "Prüfe den Betrag."}
    ]

    ChatAPI.answer("Lies den Beleg.", messages, %{})

    assert_received {:request, _path, _headers, body}

    assert body["messages"] == [
             %{"role" => "system", "content" => "Lies den Beleg."},
             %{"role" => "user", "content" => "Beleg"},
             %{"role" => "assistant", "content" => ~s({"kind":"other"})},
             %{"role" => "user", "content" => "Prüfe den Betrag."}
           ]
  end

  test "asks a thinking model not to think unless thinking is on" do
    configure(url: serve(200, completion("{}")), model: "qwen3")
    ChatAPI.answer("", [{:user, ""}], %{})
    assert_received {:request, _path, _headers, %{"reasoning_effort" => "none"}}

    configure(url: serve(200, completion("{}")), model: "qwen3", thinking: true)
    ChatAPI.answer("", [{:user, ""}], %{})
    assert_received {:request, _path, _headers, body}
    refute Map.has_key?(body, "reasoning_effort")
  end

  test "takes a thinking model's answer from its reasoning when the content is empty" do
    response = JSON.encode!(%{choices: [%{message: %{content: "", reasoning_content: "{}"}}]})
    configure(url: serve(200, response), model: "qwen3")

    assert ChatAPI.answer("", [{:user, ""}], %{}) == {:ok, "{}"}
  end

  test "sends no key without one" do
    configure(url: serve(200, completion("{}")), model: "qwen3", api_key: "")

    ChatAPI.answer("", [{:user, ""}], %{})

    assert_received {:request, _path, headers, _body}
    refute List.keymember?(headers, "authorization", 0)
  end

  test "reports a failed request or an answer without content" do
    configure(url: serve(500, "boom"), model: "qwen3")
    assert ChatAPI.answer("", [{:user, ""}], %{}) == {:error, {:http_status, 500}}

    configure(url: serve(200, ~s({"error": "no"})), model: "qwen3")
    assert ChatAPI.answer("", [{:user, ""}], %{}) == {:error, :invalid_response}
  end
end
