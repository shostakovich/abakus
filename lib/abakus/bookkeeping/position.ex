defmodule Abakus.Bookkeeping.Position do
  @moduledoc """
  A position of an invoice: what was done, how much of it in which unit, and the net price of one unit in cents.
  Its net amount is quantity × price, rounded to the cent.
  """

  use Ecto.Schema

  import Ecto.Changeset
  import Abakus.Bookkeeping.NumberInput

  alias Abakus.Money

  @units [
    {"HUR", "Stunden", "Std."},
    {"DAY", "Tage", "Tage"},
    {"C62", "Stück", "Stk."},
    {"LS", "Pauschal", "pauschal"}
  ]

  @primary_key false
  embedded_schema do
    field :description, :string
    field :quantity, :decimal
    field :unit, :string, default: "HUR"
    field :unit_price, :integer
  end

  @doc "The units of measure (UN/ECE Recommendation 20) a position offers, for a select."
  def unit_options, do: for({code, label, _short} <- @units, do: {label, code})

  @doc "The short name of a unit after a quantity: `\"Std.\"`."
  def unit_short(code), do: @units |> List.keyfind(code, 0) |> elem(2)

  def changeset(position, attrs) do
    position
    |> cast(attrs, [:description, :unit])
    |> cast_number(attrs, :quantity, &Money.parse_number/1, "ist keine Zahl")
    |> cast_cents(attrs, :unit_price)
    |> update_change(:description, &String.trim/1)
    |> validate_required([:description, :quantity, :unit, :unit_price])
    |> validate_length(:description, max: 500)
    |> validate_inclusion(:unit, Enum.map(@units, &elem(&1, 0)))
    |> validate_number(:quantity, greater_than: 0, less_than: 1_000_000)
    |> validate_number(:unit_price, greater_than_or_equal_to: 0, less_than: Money.max_cents())
  end

  @doc "The net amount in cents."
  def net(%__MODULE__{quantity: quantity, unit_price: price}),
    do: quantity |> Decimal.mult(price) |> Decimal.round(0, :half_up) |> Decimal.to_integer()
end
