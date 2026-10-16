defmodule Abakus.Kasse.Rates do
  @moduledoc """
  The Kasse's exchange rates: a manual rate wins over the ECB rates, and every change to the
  manual rates is logged.
  """

  alias Abakus.{ExchangeRates, LocalTime, Repo}
  alias Abakus.Kasse.{Activities, Dates, Money}

  @lookback_days 10

  @type rate :: %{
          currency: String.t(),
          date: Date.t(),
          source: :ecb | :manual | :fixed,
          rate: float()
        }

  @doc """
  The rate of `currency` on `date`, a date after today counting as today: the newest manual rate
  valid then, however old, or else the ECB rate of that day or of up to ten days before
  (weekends, holidays). Euros are 1. The rate is a float, as the Kasse converts with it. Option
  `:today`.
  """
  @spec rate(String.t(), Date.t(), keyword()) :: {:ok, rate()} | {:error, :no_rate}
  def rate(currency, date, opts \\ []) do
    code = Money.normalize_currency(currency)
    today = Keyword.get_lazy(opts, :today, &LocalTime.today/0)

    cond do
      code == "EUR" -> {:ok, %{currency: "EUR", source: :fixed, date: date, rate: 1.0}}
      Money.valid_currency?(code) -> lookup(code, Enum.min([date, today], Date))
      true -> {:error, :no_rate}
    end
  end

  defp lookup(code, date) do
    case ExchangeRates.newest(code, :manual, date) ||
           ExchangeRates.newest(code, :ecb, date, not_before: Date.add(date, -@lookback_days)) do
      nil ->
        {:error, :no_rate}

      rate ->
        {:ok,
         %{
           currency: code,
           date: rate.date,
           source: rate.source,
           rate: Decimal.to_float(rate.rate)
         }}
    end
  end

  @doc "Saves a manual rate for a currency from a date on, replacing one of the same day; logged."
  def put_manual_rate(actor_id, attrs) do
    Repo.transact(fn ->
      with {:ok, rate} <- ExchangeRates.put_manual_rate(attrs),
           {:ok, _activity} <-
             Activities.log_settings(
               actor_id,
               "Manueller Kurs für #{rate.currency} ab #{Dates.format(rate.date)} gespeichert: " <>
                 "1 € = #{Money.format_rate(Decimal.to_float(rate.rate))} #{rate.currency}"
             ) do
        {:ok, rate}
      end
    end)
  end

  @doc "Deletes the manual rate of a currency from a date on, logged; the ECB rates stay."
  def delete_manual_rate(actor_id, currency, date) do
    currency = Money.normalize_currency(currency)

    Repo.transact(fn ->
      with :ok <- ExchangeRates.delete_manual_rate(currency, date) do
        Activities.log_settings(
          actor_id,
          "Manueller Kurs für #{currency} ab #{Dates.format(date)} gelöscht"
        )
      end
    end)
  end
end
