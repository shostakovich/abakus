defmodule Abakus.Paperless.APITest do
  use ExUnit.Case, async: true

  alias Abakus.Paperless.API

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
      params = conn.query_params
      documents = Agent.get(state, & &1.documents)

      cond do
        params["checksum__iexact"] -> by_checksum(conn, params["checksum__iexact"], documents)
        params["content__icontains"] -> search(conn, params, documents)
        true -> tagged(conn, params, documents)
      end
    end

    defp route(conn, "GET", ["api", "documents", id], state) do
      "id,title,created,content,original_file_name" = conn.query_params["fields"]

      case Enum.find(Agent.get(state, & &1.documents), &(to_string(&1.id) == id)) do
        nil -> json(conn, 404, %{detail: "Not found."})
        document -> json(conn, 200, result(document))
      end
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

    defp route(conn, "POST", ["api", "documents", "post_document"], state) do
      conn = Plug.Parsers.call(conn, Plug.Parsers.init(parsers: [:multipart], pass: ["*/*"]))
      %{"document" => %Plug.Upload{path: path, filename: filename}} = conn.body_params

      Agent.update(state, &Map.put(&1, :uploaded, {filename, File.read!(path)}))
      json(conn, 200, "task-1")
    end

    defp route(conn, "GET", ["api", "tasks"], state) do
      "task-1" = conn.query_params["task_id"]

      task =
        Agent.get_and_update(state, fn %{tasks: [task | rest]} = s ->
          {task, %{s | tasks: rest}}
        end)

      json(conn, 200, [task])
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

    defp by_checksum(conn, checksum, documents) do
      results =
        for document <- documents,
            checksum in [hash(:md5, document.pdf), hash(:sha256, document.pdf)],
            do: %{id: document.id}

      json(conn, 200, %{count: length(results), next: nil, results: results})
    end

    defp hash(algorithm, content),
      do: algorithm |> :crypto.hash(content) |> Base.encode16(case: :lower)

    defp search(conn, params, documents) do
      "id,title,created,content,original_file_name" = params["fields"]
      "25" = params["page_size"]
      from = Date.from_iso8601!(params["created__date__gte"])
      to = Date.from_iso8601!(params["created__date__lte"])

      results =
        for document <- documents,
            String.contains?(document.content, params["content__icontains"]),
            day = Date.from_iso8601!(String.slice(document.created, 0, 10)),
            Date.compare(day, from) != :lt and Date.compare(day, to) != :gt,
            do: result(document)

      json(conn, 200, %{count: length(results), next: nil, results: results})
    end

    defp result(document) do
      %{
        id: document.id,
        title: document.title,
        created: document.created,
        content: document.content,
        original_file_name: "scan.pdf"
      }
    end

    defp tagged(conn, params, documents) do
      tag = String.to_integer(params["tags__id__all"])
      "100" = params["page_size"]

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
               %{
                 id: 1,
                 title: "Abrechnung",
                 created: "2026-10-01T00:00:00+02:00",
                 content: "Wertpapierabrechnung über 1.234,56 EUR",
                 pdf: "%PDF-1 one",
                 tags: [1, 2]
               },
               %{
                 id: 2,
                 title: "Gutschrift",
                 created: "2026-10-20",
                 content: "Ertragsgutschrift über 19,90 EUR",
                 pdf: "%PDF-1 two",
                 tags: [3]
               }
             ],
             tasks: []
           }
         end}
      )

    server = {Bandit, plug: {Stub, state}, ip: :loopback, port: 0, startup_log: false}
    {:ok, {_ip, port}} = server |> start_supervised!() |> ThousandIsland.listener_info()
    %{state: state, connection: %{url: "http://127.0.0.1:#{port}/", token: "secret"}}
  end

  test "lists the documents with a tag, whatever its case", %{connection: connection} do
    assert {:ok,
            [
              %{
                id: 1,
                content: "Wertpapierabrechnung über 1.234,56 EUR",
                filename: "scan.pdf",
                tags: [1, 2]
              }
            ]} =
             API.documents(connection, "Abakus")
  end

  test "lists no documents for a tag Paperless does not have", %{connection: connection} do
    assert API.documents(connection, "fehlt") == {:ok, []}
  end

  test "tells a wrong token", %{connection: connection} do
    assert API.documents(%{connection | token: "wrong"}, "abakus") ==
             {:error, {:http_status, 401}}
  end

  test "downloads the original PDF, else the archived one", %{connection: connection} do
    assert API.download(connection, 1) == {:ok, "%PDF-1.4 original"}
    assert API.download(connection, 2) == {:ok, "%PDF-1.7 archived"}
  end

  test "swaps the tag, creating the new one, and keeps the others, also one added meanwhile",
       ctx do
    {:ok, [document]} = API.documents(ctx.connection, "abakus")

    Agent.update(ctx.state, fn state ->
      update_in(state.documents, fn [first | rest] ->
        [%{first | tags: first.tags ++ [3]} | rest]
      end)
    end)

    assert API.swap_tag(ctx.connection, document, "abakus", "abakus-erledigt") ==
             :ok

    state = Agent.get(ctx.state, & &1)
    assert state.tags[100] == "abakus-erledigt"
    assert hd(state.documents).tags == [2, 3, 100]
    assert API.documents(ctx.connection, "abakus") == {:ok, []}
  end

  test "finds the documents with a text, created in a time span, with title and date", ctx do
    assert {:ok, [%{id: 2, title: "Gutschrift", created: ~D[2026-10-20], filename: "scan.pdf"}]} =
             API.search(ctx.connection, "19,90", ~D[2026-10-01], ~D[2026-10-31])

    assert {:ok, []} = API.search(ctx.connection, "19,90", ~D[2026-09-01], ~D[2026-10-19])

    assert {:ok, [%{id: 1, created: ~D[2026-10-01]}]} =
             API.search(ctx.connection, "1.234,56", ~D[2026-10-01], ~D[2026-10-01])
  end

  test "reads a document", %{connection: connection} do
    assert {:ok, %{id: 1, title: "Abrechnung", created: ~D[2026-10-01]}} =
             API.document(connection, 1)

    assert API.document(connection, 9) == {:error, {:http_status, 404}}
  end

  test "uploads a file and waits until Paperless has consumed it", ctx do
    Agent.update(ctx.state, fn state ->
      %{
        state
        | tasks: [
            %{task_id: "task-1", status: "PENDING", related_document: nil},
            %{task_id: "task-1", status: "SUCCESS", related_document: "7"}
          ]
      }
    end)

    assert API.upload(ctx.connection, "%PDF-1 new", "Beleg RE/2025/7 \"Mai\".pdf") == {:ok, 7}
    assert Agent.get(ctx.state, & &1.uploaded) == {"Beleg RE_2025_7 _Mai_.pdf", "%PDF-1 new"}
  end

  test "takes the document a duplicate is of", ctx do
    Agent.update(ctx.state, fn state ->
      %{state | tasks: [%{status: "failure", result_data: %{duplicate_of: 5}}]}
    end)

    assert API.upload(ctx.connection, "%PDF-1 new", "scan.pdf") == {:ok, 5}
  end

  test "links a file Paperless has by its checksum without uploading it", ctx do
    assert API.upload(ctx.connection, "%PDF-1 two", "scan.pdf") == {:ok, 2}
    refute Map.has_key?(Agent.get(ctx.state, & &1), :uploaded)
  end

  test "tells a file Paperless did not consume", ctx do
    Agent.update(ctx.state, &%{&1 | tasks: [%{status: "FAILURE", related_document: nil}]})

    assert API.upload(ctx.connection, "%PDF-1 new", "scan.pdf") == {:error, :not_consumed}
  end

  test "gives up on a file Paperless takes too long for", ctx do
    Agent.update(ctx.state, &%{&1 | tasks: List.duplicate(%{status: "STARTED"}, 10_000)})

    assert API.upload(ctx.connection, "%PDF-1 new", "scan.pdf") == {:error, :consuming}
  end
end
