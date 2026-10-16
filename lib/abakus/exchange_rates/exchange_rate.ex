defmodule Abakus.ExchangeRates.ExchangeRate do
  @moduledoc "A rate as quoted: 1 EUR = `rate` units of `currency` on `date`, from the ECB or entered by hand."
  use Abakus.Schema

  schema "exchange_rates" do
    field :currency, :string
    field :date, :date
    field :source, Ecto.Enum, values: [:ecb, :manual]
    field :rate, :decimal
  end
end
