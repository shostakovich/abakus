defmodule Abakus.Depot.Receipts.PaperlessAPITest do
  use ExUnit.Case, async: true

  alias Abakus.Depot.Receipts.PaperlessAPI

  # A small Paperless: its tags and documents in an Agent, behind the API token „secret“.
  defmodule Stub do
    @behaviour Plug

    import Plug.Conn

    @impl true
    def init(state), do: state

    @impl true
    def call(conn, state) do
      conn = fetch_query_params(conn)

      if get_req_header(conn, "authorization") == ["Token secret"],
        do: route(conn, conn.method, conn.path_info, state),
        else: send_resp(conn, 401, ~s({"detail": "Invalid token."}))
    end

    defp route(conn, "GET", ["api", "tags"], state) do
      name = String.downcase(conn.query_params["name__iexact"])
      tags = Agent.get(state, & &1.tags)

      json(conn, 200, %{
        results: for({id, n} <- tags, String.downcase(n) == name, do: %{id: id, name: n})
      })
    end

    defp route(conn, "POST", ["api", "tags"], state) do
      {:ok, body, conn} = read_body(conn)
      %{"name" => name, "matching_algorithm" => 0} = JSON.decode!(body)
      id = Agent.get_and_update(state, &{100, %{&1 | tags: Map.put(&1.tags, 100, name)}})
      json(conn, 201, %{id: id, name: name})
    end

    defp route(conn, "GET", ["api", "documents"], state) do
      tag = String.to_integer(conn.query_params["tags__id__all"])
      "100" = conn.query_params["page_size"]
      documents = Agent.get(state, & &1.documents)

      results =
        for document <- documents, tag in document.tags do
          %{
            id: document.id,
            content: document.content,
            original_file_name: "scan.pdf",
            tags: document.tags
          }
        end

      json(conn, 200, %{count: length(results), next: nil, results: results})
    end

    defp route(conn, "GET", ["api", "documents", id, "download"], _state) do
      body =
        cond do
          id == "2" and conn.query_params["original"] == "true" -> "\xFF\xD8 a JPEG"
          conn.query_params["original"] == "true" -> "%PDF-1.4 original"
          true -> "%PDF-1.7 archived"
        end

      send_resp(conn, 200, body)
    end

    defp route(conn, "POST", ["api", "documents", "bulk_edit"], state) do
      {:ok, body, conn} = read_body(conn)

      %{
        "documents" => ids,
        "method" => "modify_tags",
        "parameters" => %{"add_tags" => add, "remove_tags" => remove}
      } = JSON.decode!(body)

      Agent.update(state, fn state ->
        %{state | documents: Enum.map(state.documents, &modify_tags(&1, ids, add, remove))}
      end)

      json(conn, 200, %{result: "OK"})
    end

    defp modify_tags(document, ids, add, remove) do
      if document.id in ids,
        do: %{document | tags: Enum.uniq((document.tags -- remove) ++ add)},
        else: document
    end

    defp json(conn, status, body) do
      conn |> put_resp_content_type("application/json") |> send_resp(status, JSON.encode!(body))
    end
  end

  setup do
    state =
      start_supervised!(
        {Agent,
         fn ->
           %{
             tags: %{1 => "abakus", 2 => "Bank", 3 => "andere"},
             documents: [
               %{id: 1, content: "Wertpapierabrechnung", tags: [1, 2]},
               %{id: 2, content: "Ertragsgutschrift", tags: [3]}
             ]
           }
         end}
      )

    server = {Bandit, plug: {Stub, state}, ip: :loopback, port: 0, startup_log: false}
    {:ok, {_ip, port}} = server |> start_supervised!() |> ThousandIsland.listener_info()
    %{state: state, connection: %{url: "http://127.0.0.1:#{port}/", token: "secret"}}
  end

  test "lists the documents with a tag, whatever its case", %{connection: connection} do
    assert {:ok, [%{id: 1, content: "Wertpapierabrechnung", filename: "scan.pdf", tags: [1, 2]}]} =
             PaperlessAPI.documents(connection, "Abakus")
  end

  test "lists no documents for a tag Paperless does not have", %{connection: connection} do
    assert PaperlessAPI.documents(connection, "fehlt") == {:ok, []}
  end

  test "tells a wrong token", %{connection: connection} do
    assert PaperlessAPI.documents(%{connection | token: "wrong"}, "abakus") ==
             {:error, {:http_status, 401}}
  end

  test "downloads the original PDF, else the archived one", %{connection: connection} do
    assert PaperlessAPI.download(connection, 1) == {:ok, "%PDF-1.4 original"}
    assert PaperlessAPI.download(connection, 2) == {:ok, "%PDF-1.7 archived"}
  end

  test "swaps the tag, creating the new one, and keeps the others, also one added meanwhile",
       ctx do
    {:ok, [document]} = PaperlessAPI.documents(ctx.connection, "abakus")

    Agent.update(ctx.state, fn state ->
      update_in(state.documents, fn [first | rest] ->
        [%{first | tags: first.tags ++ [3]} | rest]
      end)
    end)

    assert PaperlessAPI.swap_tag(ctx.connection, document, "abakus", "abakus-erledigt") ==
             :ok

    state = Agent.get(ctx.state, & &1)
    assert state.tags[100] == "abakus-erledigt"
    assert hd(state.documents).tags == [2, 3, 100]
    assert PaperlessAPI.documents(ctx.connection, "abakus") == {:ok, []}
  end
end
