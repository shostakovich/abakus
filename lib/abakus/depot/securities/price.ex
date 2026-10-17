defmodule Abakus.Depot.Securities.Price do
  @moduledoc """
  A closing price × 10⁸ per security and day. On the same day a manual price wins over one from
  Yahoo.
  """
  use Abakus.Schema

  schema "depot_prices" do
    belongs_to :security, Abakus.Depot.Securities.Security
    field :date, :date
    field :close, :integer
    field :source, Ecto.Enum, values: [:yahoo, :manual]
  end
end
