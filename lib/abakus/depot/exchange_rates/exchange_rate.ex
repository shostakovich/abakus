defmodule Abakus.Depot.ExchangeRates.ExchangeRate do
  @moduledoc "An ECB reference rate as quoted: 1 EUR = `rate` units of `currency` on `date`."
  use Abakus.Schema

  schema "depot_exchange_rates" do
    field :currency, :string
    field :date, :date
    field :rate, :decimal
  end
end
