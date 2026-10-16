defmodule Abakus.Depot.DecimalInput do
  @moduledoc """
  An Ecto type for a decimal as people type it into a form, in German or English notation:
  "1.234,56" and "1234.56" both mean 1234.56, "1.500" means 1500, while "1.5" and "0.125" keep
  the dot as decimal point. A dot after a comma is an error. A form's params keep what was typed.
  """
  use Ecto.Type

  @impl true
  def type, do: :decimal

  @impl true
  def cast(value) do
    case normalize(value) do
      :error -> :error
      normalized -> Ecto.Type.cast(:decimal, normalized)
    end
  end

  @impl true
  def load(value), do: Ecto.Type.load(:decimal, value)

  @impl true
  def dump(value), do: Ecto.Type.dump(:decimal, value)

  defp normalize(text) when is_binary(text) do
    text = String.trim(text)

    cond do
      text =~ ~r/,.*\./ -> :error
      String.contains?(text, ",") -> text |> String.replace(".", "") |> String.replace(",", ".")
      text =~ ~r/^[+-]?[1-9]\d{0,2}(\.\d{3})+$/ -> String.replace(text, ".", "")
      true -> text
    end
  end

  defp normalize(other), do: other
end
