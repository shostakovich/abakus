defmodule Abakus.Depot.Portfolios.TransactionUnit do
  @moduledoc "A fee or tax of a transaction, in euro cents."
  use Abakus.Schema

  schema "depot_transaction_units" do
    belongs_to :transaction, Abakus.Depot.Portfolios.Transaction
    field :type, Ecto.Enum, values: [:tax, :fee]
    field :amount, :integer
  end
end
