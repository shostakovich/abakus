defmodule Abakus.Depot.Receipts.Check do
  @moduledoc """
  One check of a receipt's recognised fields, see `Abakus.Depot.Receipts.Checks`: its `result`,
  `:missing` when the receipt lacks what it checks, and for the screen the `computed` amount, the
  recognised values `not_found` in the receipt's text, the portfolio the depot number belongs to
  or the day a receipt with the same reference was `booked_on`.
  """
  use Ecto.Schema

  alias Abakus.Depot.Receipts.Matching

  @primary_key false
  embedded_schema do
    field :name, Ecto.Enum, values: [:amount, :found, :isin, :depot, :reference]
    field :result, Ecto.Enum, values: [:passed, :failed, :missing, :new_security]
    field :computed, :decimal
    field :not_found, {:array, Ecto.Enum}, values: Matching.values()
    field :portfolio_id, :integer
    field :portfolio_name, :string
    field :booked_on, :date
  end
end
