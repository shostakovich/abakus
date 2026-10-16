defmodule Abakus.Depot.Portfolios.TransactionUnit do
  @moduledoc "Gross value, fee or tax of a transaction, optionally in a foreign currency with its rate."
  use Abakus.Schema

  schema "depot_transaction_units" do
    belongs_to :transaction, Abakus.Depot.Portfolios.Transaction
    field :type, Ecto.Enum, values: [:gross_value, :tax, :fee]
    field :amount, :integer
    field :currency, :string
    field :fx_amount, :integer
    field :fx_currency, :string
    field :fx_rate, :decimal
  end
end
