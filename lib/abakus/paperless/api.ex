defmodule Abakus.Paperless.API do
  @moduledoc """
  Paperless-ngx's REST API under the user's URL, authenticated by the API token. A poll takes up
  to 100 documents; the next one takes the rest, since each document taken loses its tag. A search
  takes the first 25. An upload waits up to three minutes for Paperless to consume the file
  (`:poll_interval` and `:consume_timeout` in milliseconds in the config of `Abakus.Paperless`).
  """
  @behaviour Abakus.Paperless.Client

  alias Abakus.HTTP

  @page_size 100
  @search_size 25
  @document_fields "id,title,created,content,original_file_name"

  @impl true
  def documents(connection, tag) do
    with {:ok, tag_id} when tag_id != nil <- tag_id(connection, tag),
         {:ok, %{"results" => results}} <-
           get_json(connection, "documents/",
             tags__id__all: tag_id,
             page_size: @page_size,
             ordering: "added",
             fields: "id,content,original_file_name,tags"
           ) do
      {:ok, Enum.map(results, &document/1)}
    else
      {:ok, nil} -> {:ok, []}
      {:ok, _other} -> {:error, :invalid_response}
      {:error, reason} -> {:error, reason}
    end
  end

  defp document(result) do
    %{
      id: result["id"],
      title: result["title"],
      created: date(result["created"]),
      content: result["content"],
      filename: result["original_file_name"],
      tags: result["tags"] || []
    }
  end

  defp date(<<day::binary-size(10), _time::binary>>) do
    case Date.from_iso8601(day) do
      {:ok, date} -> date
      {:error, _reason} -> nil
    end
  end

  defp date(_none), do: nil

  @impl true
  def search(connection, text, from, to) do
    case get_json(connection, "documents/",
           content__icontains: text,
           created__date__gte: Date.to_iso8601(from),
           created__date__lte: Date.to_iso8601(to),
           page_size: @search_size,
           ordering: "-created",
           fields: @document_fields
         ) do
      {:ok, %{"results" => results}} -> {:ok, Enum.map(results, &document/1)}
      {:ok, _other} -> {:error, :invalid_response}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def document(connection, id) do
    case get_json(connection, "documents/#{id}/", fields: @document_fields) do
      {:ok, %{"id" => _id} = result} -> {:ok, document(result)}
      {:ok, _other} -> {:error, :invalid_response}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def upload(connection, content, filename) do
    with {:ok, nil} <- find_file(connection, content),
         {:ok, task_id} <- post_document(connection, content, filename) do
      deadline = System.monotonic_time(:millisecond) + config(:consume_timeout, 180_000)
      await_consumption(connection, task_id, deadline)
    end
  end

  # Paperless 1 and 2 take MD5 as the checksum, later ones SHA-256.
  defp find_file(connection, content) do
    Enum.reduce_while([:md5, :sha256], {:ok, nil}, fn algorithm, found ->
      checksum = algorithm |> :crypto.hash(content) |> Base.encode16(case: :lower)

      case get_json(connection, "documents/", checksum__iexact: checksum, fields: "id") do
        # More than one would mean a Paperless that ignores the filter.
        {:ok, %{"count" => 1, "results" => [%{"id" => id}]}} -> {:halt, {:ok, id}}
        {:ok, %{"results" => _results}} -> {:cont, found}
        {:ok, _other} -> {:halt, {:error, :invalid_response}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp post_document(connection, content, filename) do
    boundary = "abakus-" <> Base.encode16(:crypto.strong_rand_bytes(12), case: :lower)

    body =
      IO.iodata_to_binary([
        "--#{boundary}\r\n",
        ~s(Content-Disposition: form-data; name="document"; filename="#{safe(filename)}"\r\n),
        "Content-Type: application/octet-stream\r\n\r\n",
        content,
        "\r\n--#{boundary}--\r\n"
      ])

    case HTTP.post(url(connection, "documents/post_document/"),
           body: {"multipart/form-data; boundary=#{boundary}", body},
           headers: headers(connection)
         ) do
      {:ok, 200, response} -> task_id(response)
      {:ok, status, _body} -> {:error, {:http_status, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp safe(filename), do: String.replace(filename, ["\"", "\r", "\n", "\\", "/"], "_")

  defp task_id(response) do
    case JSON.decode(response) do
      {:ok, task_id} when is_binary(task_id) -> {:ok, task_id}
      _other -> {:error, :invalid_response}
    end
  end

  defp await_consumption(connection, task_id, deadline) do
    with {:ok, json} <- get_json(connection, "tasks/", task_id: task_id),
         :pending <- consumed(task(json)) do
      if System.monotonic_time(:millisecond) < deadline do
        Process.sleep(config(:poll_interval, 1_000))
        await_consumption(connection, task_id, deadline)
      else
        {:error, :consuming}
      end
    end
  end

  defp task(%{"results" => [task | _rest]}), do: task
  defp task([task | _rest]), do: task
  defp task(_none), do: %{}

  # Paperless 2 names the document, also the one a duplicate is of, in `related_document`; later ones in `result_data`.
  defp consumed(task) do
    id =
      Enum.find_value(
        [
          task["related_document"],
          get_in(task, ["result_data", "document_id"]),
          get_in(task, ["result_data", "duplicate_of"])
        ],
        &to_id/1
      )

    cond do
      id ->
        {:ok, id}

      String.downcase(task["status"] || "") in ~w(success failure revoked) ->
        {:error, :not_consumed}

      true ->
        :pending
    end
  end

  defp to_id(id) when is_integer(id), do: id

  defp to_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {id, ""} -> id
      _other -> nil
    end
  end

  defp to_id(_none), do: nil

  defp config(key, default),
    do: Keyword.get(Application.get_env(:abakus, Abakus.Paperless, []), key, default)

  @impl true
  def download(connection, id) do
    path = "documents/#{id}/download/"

    with {:ok, original} <- get(connection, path, original: true) do
      if pdf?(original), do: {:ok, original}, else: get(connection, path, [])
    end
  end

  defp pdf?(content), do: String.starts_with?(content, "%PDF-")

  # Paperless changes the tags itself, so that a tag added meanwhile stays.
  @impl true
  def swap_tag(connection, %{id: id}, from, to) do
    with {:ok, from_id} <- tag_id(connection, from),
         {:ok, to_id} <- ensure_tag(connection, to) do
      body = %{
        documents: [id],
        method: "modify_tags",
        parameters: %{add_tags: [to_id], remove_tags: List.wrap(from_id)}
      }

      case HTTP.post(url(connection, "documents/bulk_edit/"),
             json: body,
             headers: headers(connection)
           ) do
        {:ok, 200, _body} -> :ok
        {:ok, status, _body} -> {:error, {:http_status, status}}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp ensure_tag(connection, name) do
    case tag_id(connection, name) do
      {:ok, nil} -> create_tag(connection, name)
      found -> found
    end
  end

  # Matching „none“, so that Paperless never puts the tag on a document by itself.
  defp create_tag(connection, name) do
    body = %{name: name, matching_algorithm: 0}

    with {:ok, 201, response} <-
           HTTP.post(url(connection, "tags/"), json: body, headers: headers(connection)),
         {:ok, %{"id" => id}} <- JSON.decode(response) do
      {:ok, id}
    else
      {:ok, status, _body} -> {:error, {:http_status, status}}
      {:error, reason} -> {:error, reason}
      _invalid -> {:error, :invalid_response}
    end
  end

  # Tag names are unique in Paperless regardless of case.
  defp tag_id(connection, name) do
    case get_json(connection, "tags/", name__iexact: name) do
      {:ok, %{"results" => [%{"id" => id} | _]}} -> {:ok, id}
      {:ok, %{"results" => []}} -> {:ok, nil}
      {:ok, _other} -> {:error, :invalid_response}
      {:error, reason} -> {:error, reason}
    end
  end

  defp get_json(connection, path, params) do
    with {:ok, body} <- get(connection, path, params) do
      case JSON.decode(body) do
        {:ok, json} -> {:ok, json}
        {:error, _reason} -> {:error, :invalid_response}
      end
    end
  end

  defp get(connection, path, params) do
    case HTTP.get(url(connection, path), params: params, headers: headers(connection)) do
      {:ok, 200, body} -> {:ok, body}
      {:ok, status, _body} -> {:error, {:http_status, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp url(connection, path), do: String.trim_trailing(connection.url, "/") <> "/api/" <> path

  defp headers(connection), do: [{"authorization", "Token " <> connection.token}]
end
