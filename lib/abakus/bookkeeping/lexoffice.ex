defmodule Abakus.Bookkeeping.Lexoffice do
  @moduledoc """
  Lexoffice's public API, reached by `client/0` with the owner's API key, for the one-off import
  (`Abakus.Bookkeeping.LexofficeImport`). The key is given as a function, so that no crash report shows it, and is
  never stored.
  """

  @type key :: (-> String.t())

  @typedoc "`:unauthorized` for a key Lexoffice refuses, `:not_found` for nothing under the path."
  @type reason :: :unauthorized | :not_found | :rate_limited | :timeout | :unreachable | term

  @doc "The JSON under the path of `segments` below `/v1/`, such as `[\"invoices\", id]`, with the query `params`."
  @callback get(key, segments :: [String.t()], params :: keyword) ::
              {:ok, term} | {:error, reason}

  @doc "The file with `id`, such as an invoice's PDF."
  @callback download(key, id :: String.t()) :: {:ok, binary} | {:error, reason}

  def client, do: Application.fetch_env!(:abakus, __MODULE__)[:client]
end
