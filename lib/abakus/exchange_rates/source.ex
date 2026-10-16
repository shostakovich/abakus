defmodule Abakus.ExchangeRates.Source do
  @moduledoc "A source of daily reference rates against the euro, as `{currency, date, rate}`."

  @type reason ::
          :unreachable | :timeout | :too_large | :invalid_response | {:http_status, pos_integer}

  @callback rates(from :: Date.t()) ::
              {:ok, [{String.t(), Date.t(), Decimal.t()}]} | {:error, reason}
end
