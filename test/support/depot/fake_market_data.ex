defmodule Abakus.Depot.FakePriceFeed do
  @moduledoc """
  The price feed in tests. Answers with the function given to `stub/1` and tells the test about
  each call as `{:chart, symbol, from}`; without a stub, Yahoo is unreachable.
  """
  @behaviour Abakus.Depot.MarketData.PriceFeed

  def stub(fun) do
    Application.put_env(:abakus, __MODULE__, {self(), fun})
    ExUnit.Callbacks.on_exit(fn -> Application.delete_env(:abakus, __MODULE__) end)
  end

  @doc "A chart in EUR with the given closes and a latest quote of `quote_close`."
  def chart_result(closes, quote_close \\ 16_666_000_000, currency \\ "EUR") do
    %{
      currency: currency,
      name: "Weltindex-ETF",
      closes: closes,
      quote: %{at: ~U[2026-10-09 15:35:00.000000Z], date: ~D[2026-10-09], close: quote_close}
    }
  end

  @impl true
  def chart(symbol, from, now) do
    case Application.get_env(:abakus, __MODULE__) do
      {test, fun} ->
        send(test, {:chart, symbol, from})
        fun.(symbol, from, now)

      nil ->
        {:error, :unreachable}
    end
  end
end

defmodule Abakus.Depot.FakeSymbolSearch do
  @moduledoc """
  The symbol search in tests, like `Abakus.Depot.FakePriceFeed`; reports `{:search, query}`.
  Without a stub, Yahoo is unreachable.
  """
  @behaviour Abakus.Depot.MarketData.SymbolSearch

  def stub(fun) do
    Application.put_env(:abakus, __MODULE__, {self(), fun})
    ExUnit.Callbacks.on_exit(fn -> Application.delete_env(:abakus, __MODULE__) end)
  end

  @impl true
  def search(query) do
    case Application.get_env(:abakus, __MODULE__) do
      {test, fun} ->
        send(test, {:search, query})
        fun.(query)

      nil ->
        {:error, :unreachable}
    end
  end
end

defmodule Abakus.Depot.FakeSymbolSource do
  @moduledoc """
  The symbol source in tests, like `Abakus.Depot.FakePriceFeed`; reports `{:symbol, isin}`.
  Without a stub, or stubbed with `api_key: false`, it has no API key and is not available.
  """
  @behaviour Abakus.Depot.MarketData.SymbolSource

  @doc "Answers with `fun`, by default as if DivvyDiary knew no ISIN."
  def stub(fun \\ fn _isin -> {:error, :not_found} end, opts \\ []) do
    Application.put_env(
      :abakus,
      __MODULE__,
      {self(), fun, Keyword.get(opts, :api_key, true)}
    )

    ExUnit.Callbacks.on_exit(fn -> Application.delete_env(:abakus, __MODULE__) end)
  end

  @impl true
  def available?, do: match?({_test, _fun, true}, Application.get_env(:abakus, __MODULE__))

  @impl true
  def symbol(isin) do
    case Application.get_env(:abakus, __MODULE__) do
      {test, fun, _api_key} ->
        send(test, {:symbol, isin})
        fun.(isin)

      nil ->
        {:error, :unreachable}
    end
  end
end
