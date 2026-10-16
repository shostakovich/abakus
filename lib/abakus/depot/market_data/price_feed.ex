defmodule Abakus.Depot.MarketData.PriceFeed do
  @moduledoc """
  A source of daily closing prices and the latest quote of a symbol. Prices are × 10⁸; `closes`
  holds finished trading days only, `from` nil asks for the whole history. `name` is what the
  source calls the security, nil when it gives no name.
  """

  @type quote_ :: %{at: DateTime.t(), date: Date.t(), close: integer}
  @type chart :: %{
          currency: String.t(),
          name: String.t() | nil,
          closes: [{Date.t(), integer}],
          quote: quote_
        }
  @type reason ::
          :not_found | :unreachable | :timeout | :invalid_response | {:http_status, pos_integer}

  @callback chart(symbol :: String.t(), from :: Date.t() | nil, now :: DateTime.t()) ::
              {:ok, chart} | {:error, reason}
end
