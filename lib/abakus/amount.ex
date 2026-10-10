defmodule Abakus.Amount do
  @moduledoc """
  Amounts are integer cents, at most 100 billion euros either way: far beyond any household, and sums of them stay
  within SQLite's 64-bit integers.
  """

  @max 10_000_000_000_000
  @out_of_range "muss zwischen -100.000.000.000 € und 100.000.000.000 € liegen"

  def validate(changeset, field \\ :amount) do
    Ecto.Changeset.validate_number(changeset, field,
      greater_than_or_equal_to: -@max,
      less_than_or_equal_to: @max,
      message: @out_of_range
    )
  end

  @doc "Whether cents are within the range, for amounts that go into no changeset."
  def valid?(cents) when is_integer(cents), do: abs(cents) <= @max

  def out_of_range_message, do: @out_of_range
end
