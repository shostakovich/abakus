defmodule Abakus.Depot.Performance.CapitalGains do
  @moduledoc """
  The realised and unrealised capital gains over an interval by FIFO, as PP's
  `CapitalGainsCalculation` (read, not copied) computes them for its performance breakdown:
  against gross values, as the breakdown shows the fees and taxes of the trades on their own.

  - Each holding of the filter's portfolios on the reference day is a lot at its value then, each
    purchase or inbound delivery after it a lot at its gross value.
  - A sale or outbound delivery takes the oldest lots of its portfolio; it realises its gross
    value less their part of the lots' value. A transfer moves lots to the other portfolio.
  - The unrealised gain of a security is the value of its holdings on the last day less what is
    left of its lots, only where any are held then. Untouched lots of the reference day in another
    currency count at their joint value.
  - Each security's trades are sorted on their own, as PP sorts them: those of a day without
    times in the order purchases, transfers, sales.

  Pure; amounts in euro cents, rounded as PP rounds them.
  """

  alias Abakus.Depot.Valuation
  alias Abakus.Depot.Valuation.{Filter, Market}

  @purchases [:buy, :inbound_delivery]
  @sales [:sell, :outbound_delivery]

  @doc """
  `%{realized: cents, unrealized: cents}` over `interval`, its first day the reference day.
  `transactions` give the holdings, `trades` are the transactions after the reference day as
  `Filter.view/2` sees them.
  """
  def of(transactions, trades, %Market{} = market, %Filter{} = filter, %Date.Range{} = interval) do
    start = held(transactions, filter, interval.first)
    finish = held(transactions, filter, interval.last)

    trades =
      trades
      |> Enum.filter(&(&1.type in [:security_transfer | @purchases ++ @sales]))
      |> Enum.group_by(& &1.security_id)
      |> Map.new(fn {security_id, trades} -> {security_id, Enum.sort(trades, &in_order?/2)} end)

    [Map.keys(trades), Enum.map(start, & &1.security_id), Enum.map(finish, & &1.security_id)]
    |> Enum.concat()
    |> Enum.uniq()
    |> Enum.reduce(%{realized: 0, unrealized: 0}, fn security_id, totals ->
      lots = for h <- start, h.security_id == security_id, do: start_lot(h, market, interval)

      {lots, realized} =
        Enum.reduce(Map.get(trades, security_id, []), {lots, 0}, &trade/2)

      holdings = Enum.filter(finish, &(&1.security_id == security_id))

      %{
        realized: totals.realized + realized,
        unrealized: totals.unrealized + unrealized(security_id, lots, holdings, market, interval)
      }
    end)
  end

  defp held(transactions, filter, date) do
    transactions
    |> Valuation.holdings(date)
    |> Enum.filter(&Filter.portfolio?(filter, &1.portfolio_id))
  end

  defp start_lot(holding, market, interval) do
    value = Valuation.value_in_currency(holding, market, interval.first)
    currency = Market.currency(market, holding.security_id)

    %{
      portfolio_id: holding.portfolio_id,
      shares: holding.shares,
      original: holding.shares,
      value: Market.to_euros(market, value, currency, interval.first),
      value_in_currency: value,
      start: true
    }
  end

  defp trade(%{type: type} = t, {lots, realized}) when type in @purchases do
    lot = %{
      portfolio_id: t.portfolio_id,
      shares: t.shares,
      original: t.shares,
      value: Valuation.gross_value(t),
      start: false
    }

    {lots ++ [lot], realized}
  end

  defp trade(%{type: type} = t, {lots, realized}) when type in @sales do
    proceeds = Valuation.gross_value(t)

    {lots, {_left, gain}} =
      Enum.map_reduce(lots, {t.shares, 0}, fn lot, {left, gain} ->
        if lot.portfolio_id == t.portfolio_id and lot.shares > 0 and left > 0 do
          sold = min(left, lot.shares)
          cost = round_as_java(sold / lot.shares * lot.value)
          gain = gain + round_as_java(sold / t.shares * proceeds) - cost
          {%{lot | shares: lot.shares - sold, value: lot.value - cost}, {left - sold, gain}}
        else
          {lot, {left, gain}}
        end
      end)

    {lots, realized + gain}
  end

  defp trade(%{type: :security_transfer} = t, {lots, realized}) do
    {lots, _left} =
      Enum.flat_map_reduce(lots, t.shares, fn lot, left ->
        if lot.portfolio_id == t.portfolio_id and lot.shares > 0 and left > 0 do
          moved = min(left, lot.shares)
          value = round_as_java(moved / lot.shares * lot.value)

          arrived = %{
            portfolio_id: t.other_portfolio_id,
            shares: moved,
            original: moved,
            value: value,
            start: false
          }

          kept = %{lot | shares: lot.shares - moved, value: lot.value - value}
          {if(moved == lot.shares, do: [arrived], else: [kept, arrived]), left - moved}
        else
          {[lot], left}
        end
      end)

    {lots, realized}
  end

  defp unrealized(_security_id, _lots, [], _market, _interval), do: 0

  defp unrealized(security_id, lots, holdings, market, interval) do
    currency = Market.currency(market, security_id)
    value = Enum.sum_by(holdings, &Valuation.value_in_currency(&1, market, interval.last))

    Market.to_euros(market, value, currency, interval.last) -
      cost(lots, currency, market, interval.first)
  end

  defp cost(lots, "EUR", _market, _date), do: Enum.sum_by(lots, & &1.value)

  defp cost(lots, currency, market, date) do
    case Enum.split_with(lots, &(&1.start and &1.shares == &1.original)) do
      {[_, _ | _] = untouched, others} ->
        joint = Enum.sum_by(untouched, & &1.value_in_currency)
        Market.to_euros(market, joint, currency, date) + Enum.sum_by(others, & &1.value)

      _fewer ->
        Enum.sum_by(lots, & &1.value)
    end
  end

  # PP orders the trades of a day by time where both have one, else purchases, transfers, sales.
  defp in_order?(a, b) do
    if NaiveDateTime.to_date(a.date_time) != NaiveDateTime.to_date(b.date_time) or
         (timed?(a) and timed?(b)),
       do: NaiveDateTime.compare(a.date_time, b.date_time) != :gt,
       else: rank(a) <= rank(b)
  end

  defp timed?(%{date_time: date_time}), do: date_time.hour != 0 or date_time.minute != 0

  defp rank(%{type: type}) when type in @purchases, do: 1
  defp rank(%{type: :security_transfer}), do: 2
  defp rank(_sale), do: 3

  # Java's Math.round: half up, also below zero.
  defp round_as_java(float), do: floor(float + 0.5)
end
