defmodule Abakus.Depot.FakePaperless do
  @moduledoc """
  Paperless in tests: the instances given to `serve/1` by URL, each with its API token and its
  documents, which `documents/1` shows as they are now. An unknown URL is unreachable, a wrong
  token gets 401, a document `raise: true` raises when downloaded and one `swap_fails: true`
  keeps its tags, with 500.
  """
  @behaviour Abakus.Depot.Receipts.Paperless

  alias Abakus.Depot.ReceiptsFixtures

  @doc "A document with `attrs` over a PDF of its own and Paperless' text of the fixture receipt."
  def document(id, tags, attrs \\ []) do
    Map.merge(
      %{
        id: id,
        tags: tags,
        content: ReceiptsFixtures.receipt_text(),
        filename: "scan-#{id}.pdf",
        pdf: "%PDF-1.4\n% paperless #{id} #{System.unique_integer()}\n%%EOF\n"
      },
      Map.new(attrs)
    )
  end

  @doc "Serves `instances`, a map of URL to `%{token: token, documents: documents}`."
  def serve(instances) do
    ExUnit.Callbacks.start_supervised!(%{
      id: __MODULE__,
      start: {Agent, :start_link, [fn -> instances end, [name: __MODULE__]]}
    })
  end

  @doc "The documents of the instance at `url` as they are now."
  def documents(url), do: Agent.get(__MODULE__, & &1[url].documents)

  @doc "Changes the document with `id` of the instance at `url` by `attrs`."
  def update_document(url, id, attrs) do
    Agent.update(__MODULE__, fn instances ->
      update_in(instances[url].documents, &merge_document(&1, id, Map.new(attrs)))
    end)
  end

  defp merge_document(documents, id, attrs) do
    for document <- documents,
        do: if(document.id == id, do: Map.merge(document, attrs), else: document)
  end

  @impl true
  def documents(connection, tag) do
    with {:ok, instance} <- instance(connection) do
      {:ok,
       for(document <- instance.documents, tag in document.tags, do: Map.delete(document, :pdf))}
    end
  end

  @impl true
  def download(connection, id) do
    with {:ok, instance} <- instance(connection) do
      case Enum.find(instance.documents, &(&1.id == id)) do
        %{raise: true} -> raise "the fake Paperless broke on document #{id}"
        %{pdf: pdf} -> {:ok, pdf}
        nil -> {:error, {:http_status, 404}}
      end
    end
  end

  @impl true
  def swap_tag(connection, %{id: id}, from, to) do
    with {:ok, instance} <- instance(connection),
         %{swap_fails: true} <- Enum.find(instance.documents, &(&1.id == id)) do
      {:error, {:http_status, 500}}
    else
      {:error, reason} -> {:error, reason}
      _document -> retag(connection, id, from, to)
    end
  end

  defp retag(connection, id, from, to) do
    Agent.update(__MODULE__, fn instances ->
      update_in(instances[connection.url].documents, &retag_documents(&1, id, from, to))
    end)
  end

  defp retag_documents(documents, id, from, to) do
    for document <- documents do
      if document.id == id,
        do: %{document | tags: Enum.uniq(List.delete(document.tags, from) ++ [to])},
        else: document
    end
  end

  defp instance(connection) do
    case Agent.get(__MODULE__, & &1[connection.url]) do
      nil -> {:error, :unreachable}
      %{token: token} = instance when token == connection.token -> {:ok, instance}
      _wrong_token -> {:error, {:http_status, 401}}
    end
  end
end
