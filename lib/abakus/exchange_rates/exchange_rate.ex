defmodule Abakus.ExchangeRates.ExchangeRate do
  @moduledoc """
  A rate as quoted: 1 EUR = `rate` units of `currency` on `date`, from the ECB or entered by hand.
  A manual rate is valid from its date on; the ECB and a manual rate of the same day sit side by side.
  """
  use Abakus.Schema

  import Ecto.Changeset

  alias Abakus.Currency

  @max_rate 1.0e9

  @type t :: %__MODULE__{}

  schema "exchange_rates" do
    field :currency, :string
    field :date, :date
    field :source, Ecto.Enum, values: [:ecb, :manual]
    field :rate, :decimal
  end

  @doc "A manual rate entered for a currency from a date on."
  def manual_changeset(rate, attrs) do
    rate
    |> cast(attrs, [:currency, :date, :rate])
    |> update_change(:currency, &Currency.normalize/1)
    |> put_change(:source, :manual)
    |> validate_currency()
    |> validate_required(:date, message: "Bitte ein Datum angeben.")
    |> validate_required(:rate, message: "Der Kurs muss größer als 0 sein.")
    |> validate_number(:rate,
      greater_than: 0,
      less_than_or_equal_to: @max_rate,
      message: "Der Kurs muss größer als 0 sein."
    )
  end

  defp validate_currency(changeset) do
    case get_field(changeset, :currency) do
      "EUR" ->
        add_error(changeset, :currency, "Für Euro braucht es keinen Kurs.")

      currency ->
        if Currency.valid?(currency || ""),
          do: changeset,
          else:
            add_error(
              changeset,
              :currency,
              "Bitte einen dreistelligen Währungscode angeben (z. B. USD)."
            )
    end
  end
end
