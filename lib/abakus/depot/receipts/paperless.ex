defmodule Abakus.Depot.Receipts.Paperless do
  @moduledoc """
  A user's Paperless-ngx instance (ADR 0016), reached by its URL and API token: the documents
  with a tag, their PDFs, and swapping a document's tag for another one.
  """

  @type connection :: %{url: String.t(), token: String.t()}

  @typedoc "A document; implementations may add what `swap_tag/4` needs."
  @type document :: %{
          required(:id) => integer,
          required(:content) => String.t() | nil,
          required(:filename) => String.t() | nil,
          optional(atom) => term
        }

  @doc "The documents with `tag`, none when there is no such tag."
  @callback documents(connection, tag :: String.t()) :: {:ok, [document]} | {:error, term}

  @doc "The document's original PDF, else the PDF Paperless archived of it."
  @callback download(connection, id :: integer) :: {:ok, binary} | {:error, term}

  @doc "Tags `document` with `to` instead of `from`, creating the tag `to` if it is missing."
  @callback swap_tag(connection, document, from :: String.t(), to :: String.t()) ::
              :ok | {:error, term}
end
