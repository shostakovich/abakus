defmodule Abakus.Depot.MarketData.DivvyDiary do
  @moduledoc """
  Compositions and dividends from DivvyDiary's API, one request per ISIN, with the API key from
  `DIVVYDIARY_API_KEY`. Without a key it is not available.
  """
  @behaviour Abakus.Depot.MarketData.SymbolSource

  alias Abakus.Depot.MarketData.DivvyDiary.Response
  alias Abakus.Depot.MarketData.HTTP

  @url "https://api.divvydiary.com/symbols/"

  @impl true
  def available?, do: api_key() not in [nil, ""]

  @impl true
  def symbol(isin) do
    url = @url <> URI.encode(isin, &URI.char_unreserved?/1)

    case HTTP.get(url, [], [{"x-api-key", api_key()}]) do
      {:ok, 200, body} -> parse(body)
      {:ok, 404, _body} -> {:error, :not_found}
      {:ok, status, _body} -> {:error, {:http_status, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp parse(body) do
    case JSON.decode(body) do
      {:ok, json} -> Response.symbol(json)
      {:error, _reason} -> {:error, :invalid_response}
    end
  end

  defp api_key, do: Application.get_env(:abakus, __MODULE__, [])[:api_key]
end
