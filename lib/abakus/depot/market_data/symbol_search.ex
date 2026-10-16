defmodule Abakus.Depot.MarketData.SymbolSearch do
  @moduledoc """
  A search for the listings of a security, e.g. by its ISIN: each with the symbol the price feed
  knows it by, its name and its exchange, best match first.
  """

  @type listing :: %{symbol: String.t(), name: String.t(), exchange: String.t() | nil}
  @type reason :: :unreachable | :timeout | :invalid_response | {:http_status, pos_integer}

  @callback search(query :: String.t()) :: {:ok, [listing]} | {:error, reason}
end
