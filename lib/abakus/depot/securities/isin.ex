defmodule Abakus.Depot.Securities.ISIN do
  @moduledoc """
  International Securities Identification Numbers: two letters for the country, nine letters or
  digits and a check digit, which the Luhn algorithm computes over the digits with every letter
  as its number from A = 10 to Z = 35.
  """

  @doc "Whether `isin` has the form of an ISIN and the right check digit."
  def valid?(isin) when is_binary(isin) do
    String.match?(isin, ~r/\A[A-Z]{2}[A-Z0-9]{9}[0-9]\z/) and luhn?(digits(isin))
  end

  def valid?(_isin), do: false

  defp digits(isin) do
    isin
    |> String.to_charlist()
    |> Enum.flat_map(&Integer.digits(digit_value(&1)))
  end

  defp digit_value(char) when char in ?0..?9, do: char - ?0
  defp digit_value(char), do: char - ?A + 10

  # From the right, every second digit counts double, with the digits of the product summed.
  defp luhn?(digits) do
    sum =
      digits
      |> Enum.reverse()
      |> Enum.with_index()
      |> Enum.sum_by(fn
        {digit, index} when rem(index, 2) == 1 -> Enum.sum(Integer.digits(digit * 2))
        {digit, _index} -> digit
      end)

    rem(sum, 10) == 0
  end
end
