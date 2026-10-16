defmodule Abakus.Depot.ExchangeRates do
  @moduledoc """
  ECB reference rates, as quoted: 1 EUR = rate × currency. Shared by all users; the daily job
  stores them, calculations look them up.
  """

  import Ecto.Query, warn: false

  alias Abakus.Depot.ExchangeRates.ExchangeRate
  alias Abakus.Repo

  @doc "Stores `{currency, date, rate}` tuples; a rate stored again replaces the old one."
  def store(rates) do
    rates
    |> Enum.map(fn {currency, date, rate} -> %{currency: currency, date: date, rate: rate} end)
    |> Enum.chunk_every(5000)
    |> Enum.each(
      &Repo.insert_all(ExchangeRate, &1,
        on_conflict: {:replace, [:rate]},
        conflict_target: [:currency, :date]
      )
    )
  end

  @doc """
  The rates of the currencies as `{currency, date, rate}` from the last one on or before `date`
  on, so that every day from `date` on finds its rate; all of them when none is that old.
  """
  def list_rates_since(currencies, date) do
    # Per currency a range of the index on currency and date, instead of a check of every rate.
    Enum.flat_map(currencies, fn currency ->
      last_on_or_before =
        from q in ExchangeRate,
          where: q.currency == ^currency and q.date <= ^date,
          select: max(q.date)

      Repo.all(
        from r in ExchangeRate,
          where: r.currency == ^currency,
          where: r.date >= coalesce(subquery(last_on_or_before), ^~D[0001-01-01]),
          select: {r.currency, r.date, r.rate}
      )
    end)
  end

  @doc "The latest rate of `currency` with its date, nil without any."
  def latest(currency) do
    Repo.one(
      from r in ExchangeRate,
        where: r.currency == ^currency,
        order_by: [desc: r.date],
        limit: 1
    )
  end

  def last_date, do: Repo.one(from r in ExchangeRate, select: max(r.date))
end
