defmodule Abakus.Amount do
  @moduledoc """
  Amounts are integer cents, at most 100 billion euros either way: far beyond any household, and sums of them stay
  within SQLite's 64-bit integers.
  """

  @max 10_000_000_000_000

  def validate(changeset, field \\ :amount) do
    Ecto.Changeset.validate_number(changeset, field,
      greater_than_or_equal_to: -@max,
      less_than_or_equal_to: @max,
      message: "muss zwischen -100.000.000.000 € und 100.000.000.000 € liegen"
    )
  end
end
