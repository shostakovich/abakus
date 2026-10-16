defmodule Abakus.Depot.Securities.Price do
  @moduledoc """
  A closing price × 10⁸ per security and day. On the same day a price from PP wins over a manual
  one, a manual one over one from Yahoo.
  """
  use Abakus.Schema

  schema "depot_prices" do
    belongs_to :security, Abakus.Depot.Securities.Security
    field :date, :date
    field :close, :integer
    field :source, Ecto.Enum, values: [:pp, :yahoo, :manual]
  end
end
