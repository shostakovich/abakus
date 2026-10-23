defmodule Abakus.Depot.Performance.Breakdown do
  @moduledoc """
  Where the change in value over an interval came from, grouped as PP's performance calculation
  (`ClientPerformanceSnapshot`, read, not copied) groups it, from the initial value on the
  reference day to the final value on the last day:

  - `capital_gains` and `realized_capital_gains`: see `CapitalGains`
  - `earnings`: dividends and interest before their taxes and fees, less interest charged
  - `fees` and `taxes`: those of trades, dividends and interest, and those booked on their own,
    less refunds
  - `transfers`: deposits and inbound deliveries less removals and outbound deliveries

  Transactions count as `Filter.view/2` sees them, after the reference day. Pure; amounts in euro
  cents.
  """

  alias Abakus.Depot.Performance
  alias Abakus.Depot.Performance.CapitalGains
  alias Abakus.Depot.Valuation
  alias Abakus.Depot.Valuation.{Filter, Market}

  @enforce_keys [:initial_value, :final_value]
  defstruct initial_value: 0,
            capital_gains: 0,
            realized_capital_gains: 0,
            earnings: 0,
            fees: 0,
            taxes: 0,
            transfers: 0,
            final_value: 0

  @doc "The breakdown over the days of `index`, which values them for `filter`."
  def of(transactions, %Market{} = market, %Filter{} = filter, %Performance{} = index) do
    [first | _] = index.days
    last = List.last(index.days)
    interval = Date.range(first.date, last.date)

    booked =
      for t <- transactions,
          date = NaiveDateTime.to_date(t.date_time),
          Date.after?(date, interval.first) and not Date.after?(date, interval.last),
          seen <- Filter.view(filter, t),
          do: seen

    gains = CapitalGains.of(transactions, booked, market, filter, interval)

    breakdown = %__MODULE__{
      initial_value: first.value,
      capital_gains: gains.unrealized,
      realized_capital_gains: gains.realized,
      final_value: last.value
    }

    Enum.reduce(booked, breakdown, fn t, breakdown ->
      Enum.reduce(items(t), breakdown, fn {key, cents}, breakdown ->
        Map.update!(breakdown, key, &(&1 + cents))
      end)
    end)
  end

  defp items(%{type: type} = t) when type in [:dividend, :interest],
    do: [earnings: Valuation.gross_value(t), fees: units(t, :fee), taxes: units(t, :tax)]

  defp items(%{type: :interest_charge} = t), do: [earnings: -t.amount]
  defp items(%{type: :deposit} = t), do: [transfers: t.amount]
  defp items(%{type: :removal} = t), do: [transfers: -t.amount]
  defp items(%{type: :fee} = t), do: [fees: t.amount]
  defp items(%{type: :fee_refund} = t), do: [fees: -t.amount]
  defp items(%{type: :tax} = t), do: [taxes: t.amount]
  defp items(%{type: :tax_refund} = t), do: [taxes: -t.amount]
  defp items(%{type: :cash_transfer}), do: []

  defp items(%{type: type} = t) do
    transfers =
      case type do
        :inbound_delivery -> t.amount
        :outbound_delivery -> -t.amount
        _trade_or_transfer -> 0
      end

    [transfers: transfers, fees: units(t, :fee), taxes: units(t, :tax)]
  end

  defp units(t, type), do: t.units |> Enum.filter(&(&1.type == type)) |> Enum.sum_by(& &1.amount)
end
