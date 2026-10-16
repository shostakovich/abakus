defmodule Abakus.Depot.MarketData.SymbolSource do
  @moduledoc """
  A source of the composition of a security, its weights per country, as ISO 3166 code, and per
  sector, and its dividends, by its ISIN in one request. Without its API key it is not available
  and must not be asked.
  """

  @type composition :: %{countries: %{String.t() => number}, sectors: %{String.t() => number}}
  @type dividend :: %{
          ex_date: Date.t() | nil,
          pay_date: Date.t(),
          per_share: integer,
          currency: String.t()
        }
  @type symbol :: %{composition: composition, dividends: [dividend]}
  @type reason ::
          :not_found
          | :unreachable
          | :timeout
          | :too_large
          | :invalid_response
          | {:http_status, pos_integer}

  @callback available?() :: boolean
  @callback symbol(isin :: String.t()) :: {:ok, symbol} | {:error, reason}
end
