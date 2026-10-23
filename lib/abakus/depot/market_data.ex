defmodule Abakus.Depot.MarketData do
  @moduledoc """
  Fetches prices and the compositions and dividends of the securities and stores them. The daily
  job calls `run_daily/1`; pages refresh stale quotes in the background and hear about every
  update over PubSub. Screens never call a source themselves.
  """

  require Logger

  alias Abakus.Depot.MarketData.JobRun
  alias Abakus.Depot.Securities
  alias Abakus.Repo
  alias Abakus.Users.Scope

  @topic "market_data"
  @stale_after_seconds 15 * 60

  def subscribe, do: Phoenix.PubSub.subscribe(Abakus.PubSub, @topic)

  @doc "Tells every page that prices or holdings changed, so that it loads them again."
  def broadcast, do: Phoenix.PubSub.broadcast(Abakus.PubSub, @topic, :market_data_updated)

  @doc """
  Fetches the prices of every Yahoo security and, with an API key, the composition and the
  dividends of every security with an ISIN, then records the run. A step that fails, even with
  an exception or an exit, is recorded or logged and does not stop the others.
  """
  def run_daily(now \\ DateTime.utc_now()) do
    for security <- Securities.list_yahoo_securities() do
      update_prices_safely(security, Securities.last_price_date(security), now)
    end

    if divvy_diary_available?() do
      Enum.each(Securities.list_securities_with_isin(), &update_symbol(&1, now))
    end

    record_run(now)
    broadcast()
  end

  @doc "Whether compositions and dividends can be fetched, i.e. their source has its API key."
  def divvy_diary_available?, do: symbol_source().available?()

  def last_run, do: Repo.get_by(JobRun, name: "daily")

  defp record_run(now) do
    Repo.insert!(%JobRun{name: "daily", ran_at: now},
      on_conflict: {:replace, [:ran_at]},
      conflict_target: :name
    )
  end

  @euro_exchanges ~w(GER FRA STU MUN DUS HAM BER AMS PAR MIL BRU MCE VIE)

  @doc """
  The name and Yahoo symbol of the security with `isin`, from the price feed's search. A search by
  ISIN often finds one listing only, often in London, so a search by its name adds the listings
  of the same name; the first on an exchange in euros wins, Xetra first, else the first found.
  `:not_found` when the search has none.
  """
  def lookup_isin(isin) do
    case symbol_search().search(isin) do
      {:ok, []} ->
        {:error, :not_found}

      {:ok, [first | _] = listings} ->
        listing = preferred_listing(listings ++ same_name_listings(first.name))
        {:ok, Map.take(listing, [:name, :symbol])}

      {:error, reason} ->
        {:error, reason}
    end
  catch
    :exit, _reason -> {:error, :unreachable}
  end

  defp same_name_listings(name) do
    case symbol_search().search(name) do
      {:ok, listings} -> Enum.filter(listings, &(&1.name == name))
      {:error, _reason} -> []
    end
  end

  defp preferred_listing([first | _] = listings) do
    Enum.find_value(@euro_exchanges, first, fn exchange ->
      Enum.find(listings, &(&1.exchange == exchange))
    end)
  end

  @doc "A sentence on why `lookup_isin/1` found nothing."
  def lookup_error(:not_found), do: "Yahoo kennt diese ISIN nicht."
  def lookup_error(reason), do: source_error("Yahoo", reason)

  @doc """
  The security that takes its prices from the Yahoo symbol in `attrs`: an existing one, or one
  created with the name, currency and price history Yahoo gives. Returns the form with the error
  when the symbol is invalid or Yahoo cannot deliver it.
  """
  def create_yahoo_security(%Scope{} = scope, attrs, now \\ DateTime.utc_now()) do
    changeset = Securities.change_yahoo_symbol(attrs)

    with {:ok, %{symbol: symbol}} <- Ecto.Changeset.apply_action(changeset, :insert) do
      case Securities.get_yahoo_security(symbol) do
        nil -> fetch_new_security(scope, changeset, symbol, now)
        security -> {:ok, security}
      end
    end
  end

  defp fetch_new_security(scope, changeset, symbol, now) do
    case price_feed().chart(symbol, nil, now) do
      {:ok, chart} ->
        {:ok, security} = Securities.create_yahoo_security(scope, symbol, chart, now)
        broadcast()
        {:ok, security}

      {:error, reason} ->
        symbol_error(changeset, fetch_error(reason, %{symbol: symbol}))
    end
  catch
    :exit, _reason ->
      symbol_error(changeset, exited("the prices of #{symbol}", "Die Kurse"))
  end

  defp symbol_error(changeset, message) do
    {:error, changeset |> Ecto.Changeset.add_error(:symbol, message) |> Map.put(:action, :insert)}
  end

  @doc "Fetches, in the background, the whole price history of a security, e.g. after a new symbol."
  def fetch_in_background(security),
    do: in_background(fn -> update_prices_safely(security, nil, DateTime.utc_now()) end)

  @doc """
  Refreshes, in the background, every Yahoo quote not checked for 15 minutes, failed ones too.
  Each check is claimed first, so pages opened together fetch a quote once.
  """
  def refresh_stale_quotes(now \\ DateTime.utc_now()) do
    cutoff = DateTime.add(now, -@stale_after_seconds)

    case Securities.claim_unchecked_yahoo_securities(cutoff, now) do
      [] -> :ok
      stale -> in_background(fn -> Enum.each(stale, &refresh_quote(&1, now)) end)
    end
  end

  defp in_background(fun) do
    {:ok, _pid} =
      Task.Supervisor.start_child(Abakus.Depot.TaskSupervisor, fn ->
        fun.()
        broadcast()
      end)

    :ok
  end

  defp update_prices_safely(security, from, now) do
    update_prices(security, from, now)
  rescue
    exception ->
      message = log_and_describe(exception, __STACKTRACE__, "Die Kurse")
      record_failure(security, message, now)
  catch
    :exit, _reason ->
      record_failure(security, exited("the prices of #{security.symbol}", "Die Kurse"), now)
  end

  # Recording fails too when the database is the problem; the log has it then.
  defp record_failure(security, message, now) do
    Securities.with_same_yahoo_symbol(security, &Securities.record_fetch_error(&1, message, now))
  rescue
    _exception -> :error
  end

  defp update_prices(security, from, now) do
    with {:ok, chart} <- fetch(security, not_after(from, DateTime.to_date(now)), now) do
      Securities.with_same_yahoo_symbol(security, fn current ->
        Securities.store_yahoo_prices(current, chart.closes)
        Securities.record_quote(current, chart.quote, now)
      end)
    end
  end

  # A failed fetch keeps the stored composition; one DivvyDiary does not know is no error.
  defp update_symbol(security, now) do
    case symbol_source().symbol(security.isin) do
      {:ok, %{composition: composition, dividends: dividends}} ->
        Securities.replace_composition(security, composition, now)
        Securities.replace_dividends(security, dividends, now)

      {:error, :not_found} ->
        :ok

      {:error, reason} ->
        Logger.warning("Nothing from DivvyDiary for #{security.isin}: #{inspect(reason)}")
    end
  rescue
    exception -> Logger.error(Exception.format(:error, exception, __STACKTRACE__))
  catch
    # The reason of an exit from `:httpc` holds the request, the API key with it.
    :exit, _reason ->
      Logger.error("Nothing from DivvyDiary for #{security.isin}: the request exited")
  end

  # Yahoo refuses a start after the end.
  defp not_after(nil, _today), do: nil
  defp not_after(date, today), do: Enum.min([date, today], Date)

  # Only the latest quote: today's closing price comes with the daily run.
  defp refresh_quote(security, now) do
    with {:ok, chart} <- fetch(security, DateTime.to_date(now), now) do
      Securities.with_same_yahoo_symbol(security, &Securities.record_quote(&1, chart.quote, now))
    end
  end

  # A changed symbol makes the result void, the error included.
  defp fetch(security, from, now) do
    with {:ok, chart} <- price_feed().chart(security.symbol, from, now),
         :ok <- check_currency(chart, security) do
      {:ok, chart}
    else
      {:error, reason} ->
        message = fetch_error(reason, security)

        Securities.with_same_yahoo_symbol(
          security,
          &Securities.record_fetch_error(&1, message, now)
        )

        {:error, reason}
    end
  end

  defp log_and_describe(exception, stacktrace, what) do
    Logger.error(Exception.format(:error, exception, stacktrace))
    "#{what} ließen sich nicht speichern: #{Exception.message(exception)}"
  end

  # The reason of an exit, e.g. from `:httpc`, may hold the request with its credentials.
  defp exited(logged, what) do
    Logger.error("The request for #{logged} exited")
    "#{what} ließen sich nicht abrufen."
  end

  defp check_currency(%{currency: currency}, %{currency: expected})
       when expected in [nil, currency], do: :ok

  defp check_currency(%{currency: currency}, _security),
    do: {:error, {:currency_mismatch, currency}}

  defp fetch_error(:not_found, security), do: "Yahoo kennt das Symbol #{security.symbol} nicht."

  defp fetch_error({:currency_mismatch, currency}, security),
    do:
      "Yahoo notiert #{security.symbol} in #{currency}, das Wertpapier ist in #{security.currency}."

  defp fetch_error(reason, _security), do: source_error("Yahoo", reason)

  defp source_error(source, reason) when reason in [:unreachable, :timeout],
    do: "#{source} ist nicht erreichbar."

  defp source_error(source, {:http_status, status}), do: "#{source} antwortet mit HTTP #{status}."
  defp source_error(source, :too_large), do: "#{source} liefert eine zu große Antwort."
  defp source_error(source, :invalid_response), do: "#{source} liefert eine unerwartete Antwort."

  defp price_feed, do: config(:price_feed)
  defp symbol_search, do: config(:symbol_search)
  defp symbol_source, do: config(:symbol_source)
  defp config(key), do: Application.fetch_env!(:abakus, __MODULE__)[key]
end
