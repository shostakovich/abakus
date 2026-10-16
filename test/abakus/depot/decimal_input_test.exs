defmodule Abakus.Depot.DecimalInputTest do
  use ExUnit.Case, async: true

  alias Abakus.Depot.DecimalInput

  defp cast(text) do
    case DecimalInput.cast(text) do
      {:ok, decimal} -> Decimal.to_string(decimal, :normal)
      :error -> :error
    end
  end

  test "German notation with thousands and decimal comma" do
    assert cast("1.234,56") == "1234.56"
    assert cast(" 12,5 ") == "12.5"
    assert cast("1.500") == "1500"
    assert cast("1.234.567") == "1234567"
  end

  test "a dot that cannot be German thousands is a decimal point" do
    assert cast("1234.56") == "1234.56"
    assert cast("12.5") == "12.5"
    assert cast("1.5") == "1.5"
    assert cast("0.123") == "0.123"
    assert cast("12.3456") == "12.3456"
  end

  test "a dot after a comma is an error" do
    assert cast("1,234.56") == :error
  end
end
