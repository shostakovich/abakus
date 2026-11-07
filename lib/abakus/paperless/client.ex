defmodule Abakus.Paperless.Client do
  @moduledoc """
  A user's Paperless-ngx instance (ADR 0016), reached by its URL and API token: its documents, their PDFs and tags,
  and uploads to it.
  """

  @type connection :: %{url: String.t(), token: String.t()}

  @typedoc "A document; implementations may add what `swap_tag/4` needs."
  @type document :: %{
          required(:id) => integer,
          required(:content) => String.t() | nil,
          required(:filename) => String.t() | nil,
          optional(:title) => String.t() | nil,
          optional(:created) => Date.t() | nil,
          optional(atom) => term
        }

  @doc "The documents with `tag`, none when there is no such tag."
  @callback documents(connection, tag :: String.t()) :: {:ok, [document]} | {:error, term}

  @doc "The documents whose text contains `text`, created from `from` to `to`, with title and date."
  @callback search(connection, text :: String.t(), from :: Date.t(), to :: Date.t()) ::
              {:ok, [document]} | {:error, term}

  @doc "The document with `id`, with title and date."
  @callback document(connection, id :: integer) :: {:ok, document} | {:error, term}

  @doc "The document's original PDF, else the PDF Paperless archived of it."
  @callback download(connection, id :: integer) :: {:ok, binary} | {:error, term}

  @doc """
  Files `content` in Paperless and returns its document's id once Paperless has consumed it; a file Paperless has
  already, by its checksum, is that document.
  """
  @callback upload(connection, content :: binary, filename :: String.t()) ::
              {:ok, integer} | {:error, term}

  @doc "Tags `document` with `to` instead of `from`, creating the tag `to` if it is missing."
  @callback swap_tag(connection, document, from :: String.t(), to :: String.t()) ::
              :ok | {:error, term}
end
