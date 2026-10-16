defmodule Abakus.ExchangeRates do
  @moduledoc """
  Exchange rates as quoted: 1 EUR = rate × currency. The daily job loads the ECB reference rates;
  every area looks them up. The Depot reads only ECB rates.
  """

  import Ecto.Query, warn: false

  require Logger

  alias Abakus.ExchangeRates.{ExchangeRate, Run}
  alias Abakus.Repo

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

  defp ecb, do: from(r in ExchangeRate, where: r.source == :ecb)

  defp source, do: Application.fetch_env!(:abakus, __MODULE__)[:source]
end
