defmodule Abakus.Depot.DecimalInput do
  @moduledoc """
  An Ecto type for a decimal as people type it into a form, read by `Abakus.Money.parse_number/1`:
  "1.234,56" and "1,234.56" both mean 1234.56, "1.500" means 1500, while "1.5" and "0.125" keep
  the dot as decimal point. A form's params keep what was typed.
  """
  use Ecto.Type

  alias Abakus.Money

  @impl true
  def type, do: :decimal

  @impl true
  def cast(text) when is_binary(text) do
    case Money.parse_number(text) do
      {:ok, decimal} -> {:ok, decimal}
      {:error, _message} -> :error
    end
  end

  def cast(value), do: Ecto.Type.cast(:decimal, value)

  @impl true
  def load(value), do: Ecto.Type.load(:decimal, value)

  @impl true
  def dump(value), do: Ecto.Type.dump(:decimal, value)
end
