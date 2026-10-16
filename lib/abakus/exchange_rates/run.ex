defmodule Abakus.ExchangeRates.Run do
  @moduledoc "A load of the ECB rates, with its error, if any."
  use Abakus.Schema

  schema "exchange_rate_runs" do
    field :ran_at, :utc_datetime_usec
    field :error, :string
  end
end
