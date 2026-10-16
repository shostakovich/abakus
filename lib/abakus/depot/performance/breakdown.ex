defmodule Abakus.Depot.Performance.Breakdown do
  @moduledoc """
  Where the change in value over an interval came from, grouped as PP's performance calculation
  (`ClientPerformanceSnapshot`, read, not copied) groups it, from the initial value on the
  reference day to the final value on the last day:

  - `capital_gains` and `realized_capital_gains`: see `CapitalGains`
  - `earnings`: dividends and interest before their taxes and fees, less interest charged
  - `fees` and `taxes`: those of trades, dividends and interest, and those booked on their own,
    less refunds
  - `currency_gains`: what the accounts in another currency gained or lost in euros
  - `transfers`: deposits and inbound deliveries less removals and outbound deliveries

  Transactions count as `Filter.view/2` sees them, after the reference day, each in euros at the
  ECB rate of its day. Pure; amounts in euro cents.
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
            currency_gains: 0,
            transfers: 0,
            final_value: 0

  @credits [:deposit, :sell, :dividend, :interest, :tax_refund, :fee_refund]
  @debits [:removal, :buy, :interest_charge, :tax, :fee]

  @doc "The breakdown over the days of `index`, which values them for `filter`."
  def of(transactions, accounts, %Market{} = market, %Filter{} = filter, %Performance{} = index) do
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
      currency_gains: currency_gains(transactions, accounts, booked, market, filter, interval),
      final_value: last.value
    }

    Enum.reduce(booked, breakdown, fn t, breakdown ->
      Enum.reduce(items(t, market), breakdown, fn {key, cents}, breakdown ->
        Map.update!(breakdown, key, &(&1 + cents))
      end)
    end)
  end

  # What a transaction adds to each item.
  defp items(%{type: type} = t, market) when type in [:dividend, :interest] do
    gross_value = Valuation.gross_value(t, t.currency)

    [
      earnings: euros(market, gross_value, t.currency, t),
      fees: units(t, :fee, market),
      taxes: units(t, :tax, market)
    ]
  end

  defp items(%{type: :interest_charge} = t, market), do: [earnings: -euros(market, t)]
  defp items(%{type: :deposit} = t, market), do: [transfers: euros(market, t)]
  defp items(%{type: :removal} = t, market), do: [transfers: -euros(market, t)]
  defp items(%{type: :fee} = t, market), do: [fees: euros(market, t)]
  defp items(%{type: :fee_refund} = t, market), do: [fees: -euros(market, t)]
  defp items(%{type: :tax} = t, market), do: [taxes: euros(market, t)]
  defp items(%{type: :tax_refund} = t, market), do: [taxes: -euros(market, t)]
  defp items(%{type: :cash_transfer}, _market), do: []

  defp items(%{type: type} = t, market) do
    transfers =
      case type do
        :inbound_delivery -> euros(market, t)
        :outbound_delivery -> -euros(market, t)
        _trade_or_transfer -> 0
      end

    [transfers: transfers, fees: units(t, :fee, market), taxes: units(t, :tax, market)]
  end

  defp euros(market, t), do: euros(market, t.amount, t.currency, t)

  defp euros(market, amount, currency, t),
    do: Market.to_euros(market, amount, currency, NaiveDateTime.to_date(t.date_time))

  # The fees or taxes of a transaction in euros: as booked in euros, or at the ECB rate.
  defp units(t, type, market) do
    for %{type: ^type} = unit <- t.units, reduce: 0 do
      sum ->
        sum +
          cond do
            unit.currency == "EUR" -> unit.amount
            unit.fx_currency == "EUR" -> unit.fx_amount
            true -> euros(market, unit.amount, unit.currency, t)
          end
    end
  end

  # Per account in another currency: its balance in euros at the end, less at the start, less
  # what came in and plus what went out in euros on the day.
  defp currency_gains(transactions, accounts, booked, market, filter, interval) do
    start = Valuation.balances(transactions, interval.first)
    finish = Valuation.balances(transactions, interval.last)

    for %{currency: currency, id: id} <- accounts,
        currency != "EUR" and Filter.account?(filter, id),
        reduce: 0 do
      sum ->
        sum + Market.to_euros(market, Map.get(finish, id, 0), currency, interval.last) -
          Market.to_euros(market, Map.get(start, id, 0), currency, interval.first) -
          Enum.sum_by(booked, &received(&1, id, market))
    end
  end

  # What a transaction brings into an account, in euros; negative for what it takes out.
  defp received(%{type: :cash_transfer} = t, account_id, market) do
    cond do
      t.account_id == account_id -> -transferred(t, market)
      t.other_account_id == account_id -> transferred(t, market)
      true -> 0
    end
  end

  defp received(%{account_id: account_id, type: type} = t, account_id, market)
       when type in @credits,
       do: euros(market, t)

  defp received(%{account_id: account_id, type: type} = t, account_id, market)
       when type in @debits,
       do: -euros(market, t)

  defp received(_t, _account_id, _market), do: 0

  # A transfer in euros as booked on its euro side, else the mean of both sides at the ECB rate.
  defp transferred(%{currency: "EUR"} = t, _market), do: t.amount

  defp transferred(t, market) do
    case Valuation.received(t) do
      {amount, "EUR"} ->
        amount

      {amount, currency} ->
        floor((euros(market, t) + euros(market, amount, currency, t)) / 2 + 0.5)
    end
  end
end
