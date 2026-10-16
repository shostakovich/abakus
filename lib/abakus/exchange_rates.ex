defmodule Abakus.ExchangeRates do
  @moduledoc """
  Exchange rates as quoted: 1 EUR = rate × currency. The daily job loads the ECB reference rates;
  manual rates are entered by hand. Every area looks them up by its own rule.
  """

  import Ecto.Query, warn: false

  require Logger

  alias Abakus.{Currency, Repo}
  alias Abakus.ExchangeRates.{ExchangeRate, Run}

  @first_date ~D[1999-01-04]
  @topic "exchange_rates"

  @doc "Subscribes to `:exchange_rates_updated`, sent after every load."
  def subscribe, do: Phoenix.PubSub.subscribe(Abakus.PubSub, @topic)

  @doc """
  Loads the ECB rates from the last stored day on, which may still change, or from the first ECB
  day, records the run with its error and tells the subscribers. A failure, even an exception or
  an exit, is recorded and returned as `{:error, message}`.
  """
  def load(now \\ DateTime.utc_now()) do
    error = fetch_and_store()
    Repo.insert!(%Run{ran_at: now, error: error})
    Phoenix.PubSub.broadcast(Abakus.PubSub, @topic, :exchange_rates_updated)
    if error, do: {:error, error}, else: :ok
  end

  defp fetch_and_store do
    case source().rates(last_date() || @first_date) do
      {:ok, rates} ->
        store(rates)
        nil

      {:error, reason} ->
        source_error(reason)
    end
  rescue
    exception ->
      Logger.error(Exception.format(:error, exception, __STACKTRACE__))
      "Die Wechselkurse ließen sich nicht speichern: #{Exception.message(exception)}"
  catch
    :exit, _reason ->
      Logger.error("Loading the exchange rates exited")
      "Die Wechselkurse ließen sich nicht abrufen."
  end

  defp source_error(reason) when reason in [:unreachable, :timeout],
    do: "Die EZB ist nicht erreichbar."

  defp source_error({:http_status, status}), do: "Die EZB antwortet mit HTTP #{status}."
  defp source_error(:too_large), do: "Die EZB liefert eine zu große Antwort."
  defp source_error(:invalid_response), do: "Die EZB liefert eine unerwartete Antwort."

  @doc "The last load, nil before the first."
  def last_run, do: Repo.one(from r in Run, order_by: [desc: r.ran_at, desc: r.id], limit: 1)

  @doc """
  Stores ECB rates as `{currency, date, rate}`, all or none; a rate stored again replaces the old
  one.
  """
  def store(rates) do
    # The next load starts at the last stored day, so a partial store would leave gaps for good.
    {:ok, :ok} =
      Repo.transact(fn ->
        rates
        |> Enum.map(fn {currency, date, rate} ->
          %{currency: currency, date: date, source: :ecb, rate: rate}
        end)
        |> Enum.chunk_every(5000)
        |> Enum.each(
          &Repo.insert_all(ExchangeRate, &1,
            on_conflict: {:replace, [:rate]},
            conflict_target: [:currency, :source, :date]
          )
        )

        {:ok, :ok}
      end)

    :ok
  end

  @doc """
  The ECB rates of the currencies as `{currency, date, rate}` from the last one on or before
  `date` on, so that every day from `date` on finds its rate; all of them when none is that old.
  """
  def list_rates_since(currencies, date) do
    # Per currency a range of the index on currency, source and date, instead of a check of every rate.
    Enum.flat_map(currencies, fn currency ->
      last_on_or_before =
        from q in ecb(),
          where: q.currency == ^currency and q.date <= ^date,
          select: max(q.date)

      Repo.all(
        from r in ecb(),
          where: r.currency == ^currency,
          where: r.date >= coalesce(subquery(last_on_or_before), ^~D[0001-01-01]),
          select: {r.currency, r.date, r.rate}
      )
    end)
  end

  @doc "The latest ECB rate of `currency` with its date, nil without any."
  def latest(currency) do
    Repo.one(
      from r in ecb(),
        where: r.currency == ^currency,
        order_by: [desc: r.date],
        limit: 1
    )
  end

  @doc "The last day with an ECB rate, nil without any."
  def last_date, do: Repo.one(from r in ecb(), select: max(r.date))

  @doc """
  The newest rate of `currency` from `source` on or before `date`, nil without one. Option
  `:not_before` limits how old it may be.
  """
  @spec newest(String.t(), :ecb | :manual, Date.t(), keyword()) :: ExchangeRate.t() | nil
  def newest(currency, source, date, opts \\ []) do
    query =
      from r in ExchangeRate,
        where: r.currency == ^currency and r.source == ^source and r.date <= ^date,
        order_by: [desc: r.date],
        limit: 1

    query =
      case Keyword.fetch(opts, :not_before) do
        {:ok, not_before} -> where(query, [r], r.date >= ^not_before)
        :error -> query
      end

    Repo.one(query)
  end

  @doc "How many ECB rates of how many currencies are stored, from and to which day."
  @spec ecb_stats() :: %{
          count: non_neg_integer(),
          currencies: non_neg_integer(),
          from: Date.t() | nil,
          to: Date.t() | nil
        }
  def ecb_stats do
    Repo.one(
      from r in ecb(),
        select: %{
          count: count(),
          currencies: count(r.currency, :distinct),
          from: min(r.date),
          to: max(r.date)
        }
    )
  end

  @doc "The ECB rates of the newest day, by currency."
  @spec latest_ecb_rates() :: [ExchangeRate.t()]
  def latest_ecb_rates do
    Repo.all(
      from r in ecb(),
        where: r.date == subquery(from q in ecb(), select: max(q.date)),
        order_by: r.currency
    )
  end

  @doc "The currencies that have a rate, for choosing one."
  @spec list_currencies() :: [String.t()]
  def list_currencies,
    do: Repo.all(from r in ExchangeRate, distinct: true, select: r.currency, order_by: r.currency)

  @doc "The manual rates by currency, the newest first."
  @spec list_manual_rates() :: [ExchangeRate.t()]
  def list_manual_rates,
    do: Repo.all(from r in manual(), order_by: [r.currency, desc: r.date])

  @doc "A changeset for the manual rate form."
  def change_manual_rate(attrs \\ %{}), do: ExchangeRate.manual_changeset(%ExchangeRate{}, attrs)

  @doc "Saves a manual rate for a currency from a date on, replacing one of the same day."
  def put_manual_rate(attrs) do
    Repo.insert(change_manual_rate(attrs),
      on_conflict: {:replace, [:rate]},
      conflict_target: [:currency, :source, :date]
    )
  end

  @doc "Deletes the manual rate of a currency from a date on; the ECB rates stay."
  def delete_manual_rate(currency, date) do
    currency = Currency.normalize(currency)

    case Repo.delete_all(from r in manual(), where: r.currency == ^currency and r.date == ^date) do
      {0, _} -> {:error, :not_found}
      {_deleted, _} -> :ok
    end
  end

  defp ecb, do: from(r in ExchangeRate, where: r.source == :ecb)
  defp manual, do: from(r in ExchangeRate, where: r.source == :manual)

  defp source, do: Application.fetch_env!(:abakus, __MODULE__)[:source]
end
