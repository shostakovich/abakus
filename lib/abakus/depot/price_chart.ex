defmodule Abakus.Depot.PriceChart do
  @moduledoc """
  A security's price chart, as PP's security chart draws it: its prices over a period, and the
  purchases and sales as dots at their price per share. Purchases are buys and inbound
  deliveries, sales are sells and outbound deliveries; transfers between portfolios change
  nothing. Pure; prices × 10⁸ in the security's currency, shares × 10⁸.
  """

  alias Abakus.Depot.Period
  alias Abakus.Depot.Portfolios.Transaction
  alias Abakus.Depot.Securities.Security
  alias Abakus.Depot.Valuation

  @trades [:buy, :inbound_delivery, :sell, :outbound_delivery]

  @doc """
  The chart of `security` over the days of `range`, from its `closes` as `{date, close}` in order
  of date and `transactions` of it:

  - `prices`: `%{date, price}` from the closes and the latest quote unless a close is newer. For
    each day `Period.chart_days/1` keeps and each day with a trade, the last price on or before
    it, so that years of prices stay small without a trade losing the price of its day.
  - `trades`: the purchases and sales on the days of `range` by time, each with its `date`,
    `type`, `shares` and gross `price` per share, or for a security not in euros the price of its
    day; without either it is left out.
  """
  def of(%Security{} = security, closes, transactions, %Date.Range{} = range) do
    prices = with_latest_quote(closes, security)

    trades =
      transactions
      |> Enum.filter(&(&1.type in @trades and date(&1) in range))
      |> Enum.sort_by(& &1.date_time, NaiveDateTime)
      |> Enum.map(&trade(&1, security.currency, prices))
      |> Enum.reject(&is_nil(&1.price))

    days = range |> Period.chart_days() |> Enum.concat(Enum.map(trades, & &1.date))

    %{
      prices: prices |> on(days) |> Enum.reject(&Date.before?(&1.date, range.first)),
      trades: trades
    }
  end

  # PP's prices including the latest: the quote replaces a close of its day and follows older ones.
  defp with_latest_quote(closes, %Security{latest_date: %Date{} = date, latest_close: quote})
       when is_integer(quote) do
    {older, newer} = Enum.split_while(closes, fn {day, _close} -> Date.before?(day, date) end)

    if Enum.any?(newer, fn {day, _close} -> Date.after?(day, date) end),
      do: to_prices(closes),
      else: to_prices(older) ++ [%{date: date, price: quote}]
  end

  defp with_latest_quote(closes, _security), do: to_prices(closes)

  defp to_prices(closes),
    do: Enum.map(closes, fn {date, close} -> %{date: date, price: close} end)

  defp trade(%Transaction{} = t, currency, prices) do
    date = date(t)

    price =
      (currency == "EUR" && Valuation.price_per_share(t)) ||
        Enum.find_value(on(prices, [date]), & &1.price)

    %{date: date, type: t.type, shares: t.shares, price: price}
  end

  defp on(prices, days) do
    days
    |> Enum.uniq()
    |> Enum.sort(Date)
    |> Enum.map_reduce({prices, nil}, fn day, {pending, last} ->
      {passed, pending} = Enum.split_while(pending, &(not Date.after?(&1.date, day)))
      last = List.last(passed) || last
      {last, {pending, last}}
    end)
    |> elem(0)
    |> Enum.reject(&is_nil/1)
    |> Enum.dedup()
  end

  defp date(%Transaction{date_time: date_time}), do: NaiveDateTime.to_date(date_time)
end
