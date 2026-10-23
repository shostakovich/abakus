defmodule Abakus.Depot.MarketData.Yahoo do
  @moduledoc """
  Prices from Yahoo's chart API. An explicit range keeps daily data (`range=max` thins it out).
  Stores the plain close, not the adjusted one, which would count distributions twice. The name
  is Yahoo's long name, else its short one. Closes of 0 are gaps, not prices. Pence and cents are named as ISO 4217 lists them,
  `GBX` for Yahoo's `GBp` and `ZAC` for its `ZAc`. Yahoo's search finds the listings of an ISIN.
  """
  @behaviour Abakus.Depot.MarketData.PriceFeed
  @behaviour Abakus.Depot.MarketData.SymbolSearch

  alias Abakus.HTTP

  @url "https://query1.finance.yahoo.com/v8/finance/chart/"
  @search_url "https://query1.finance.yahoo.com/v1/finance/search"

  # Older daily candles use today's UTC offset, an hour off across DST, so their day is read a few hours in.
  @day_slack 3 * 60 * 60

  @impl true
  def chart(symbol, from, now) do
    params = [period1: period_start(from), period2: DateTime.to_unix(now), interval: "1d"]

    case HTTP.get(@url <> URI.encode(symbol, &URI.char_unreserved?/1),
           params: params,
           follow_redirects: true
         ) do
      {:ok, 200, body} -> parse(body, now)
      {:ok, 404, _body} -> {:error, :not_found}
      {:ok, status, _body} -> {:error, {:http_status, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp period_start(nil), do: 0
  defp period_start(date), do: date |> DateTime.new!(~T[00:00:00]) |> DateTime.to_unix()

  @doc "Reads a chart response; a day still trading at `now` is left out of the closes."
  def parse(body, now) do
    with {:ok, %{"chart" => %{"result" => [result | _]}}} <- JSON.decode(body),
         {:ok, chart} <- read(result, now) do
      {:ok, chart}
    else
      _invalid -> {:error, :invalid_response}
    end
  end

  defp read(%{"meta" => meta} = result, now) do
    offset = meta["gmtoffset"]

    {:ok,
     %{
       currency: currency(Map.fetch!(meta, "currency")),
       name: meta["longName"] || meta["shortName"],
       closes: closes(result, offset, open_since(meta, now)),
       quote: %{
         at: DateTime.from_unix!(meta["regularMarketTime"] * 1_000_000, :microsecond),
         date: local_date(meta["regularMarketTime"], offset),
         close: to_price(meta["regularMarketPrice"])
       }
     }}
  rescue
    _error -> :error
  end

  defp currency("GBp"), do: "GBX"
  defp currency("ZAc"), do: "ZAC"
  defp currency(code), do: code

  defp open_since(%{"currentTradingPeriod" => %{"regular" => regular}}, now) do
    if DateTime.to_unix(now) < regular["end"], do: regular["start"]
  end

  defp closes(
         %{"timestamp" => timestamps, "indicators" => %{"quote" => [quote | _]}},
         offset,
         open
       ) do
    timestamps
    |> Enum.zip(quote["close"])
    |> Enum.reject(fn {time, close} -> is_nil(close) or close == 0 or (open && time >= open) end)
    |> Enum.map(fn {time, close} -> {local_date(time + @day_slack, offset), to_price(close)} end)
  end

  defp closes(_result, _offset, _open), do: []

  defp local_date(unix, offset), do: DateTime.from_unix!(unix + offset) |> DateTime.to_date()

  # Yahoo sends binary floats such as 167.0399932861328 for 167.04.
  defp to_price(value) when is_integer(value), do: value * 100_000_000

  defp to_price(value) when is_float(value) do
    value
    |> Decimal.from_float()
    |> Decimal.round(4)
    |> Decimal.mult(100_000_000)
    |> Decimal.to_integer()
  end

  @impl Abakus.Depot.MarketData.SymbolSearch
  def search(query) do
    case HTTP.get(@search_url,
           params: [q: query, quotesCount: 20, newsCount: 0, listsCount: 0],
           follow_redirects: true
         ) do
      {:ok, 200, body} -> parse_search(body)
      {:ok, status, _body} -> {:error, {:http_status, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Reads a search response: the listings with a symbol, in Yahoo's order."
  def parse_search(body) do
    case JSON.decode(body) do
      {:ok, %{"quotes" => quotes}} when is_list(quotes) ->
        {:ok, for(%{"symbol" => symbol} = quote <- quotes, do: listing(symbol, quote))}

      _invalid ->
        {:error, :invalid_response}
    end
  end

  defp listing(symbol, quote) do
    %{
      symbol: symbol,
      name: quote["longname"] || quote["shortname"] || symbol,
      exchange: quote["exchange"]
    }
  end
end
