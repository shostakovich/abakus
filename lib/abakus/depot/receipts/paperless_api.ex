defmodule Abakus.Depot.Receipts.PaperlessAPI do
  @moduledoc """
  Paperless-ngx's REST API under the user's URL, authenticated by the API token. A poll takes up
  to 100 documents; the next one takes the rest, since each document taken loses its tag.
  """
  @behaviour Abakus.Depot.Receipts.Paperless

  alias Abakus.Depot.MarketData.HTTP

  @page_size 100

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
      content: result["content"],
      filename: result["original_file_name"],
      tags: result["tags"] || []
    }
  end

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

      case HTTP.post_json(url(connection, "documents/bulk_edit/"), body, headers(connection)) do
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
           HTTP.post_json(url(connection, "tags/"), body, headers(connection)),
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
    case HTTP.get(url(connection, path), params, headers(connection)) do
      {:ok, 200, body} -> {:ok, body}
      {:ok, status, _body} -> {:error, {:http_status, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp url(connection, path), do: String.trim_trailing(connection.url, "/") <> "/api/" <> path

  defp headers(connection), do: [{"authorization", "Token " <> connection.token}]
end
