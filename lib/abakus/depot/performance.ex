defmodule Abakus.Depot.Performance do
  @moduledoc """
  The true time-weighted rate of return (TTWROR) and the internal rate of return (IRR) of a
  user's portfolios and accounts, or of a `Filter` of them, over an interval such as
  `Abakus.Depot.Period.interval/3` gives, with the figures built on them: the maximum drawdown,
  the volatility, the monthly returns, and the TTWROR of a benchmark and the value of a shadow
  portfolio in it. Pure, and computed as PP 0.88 does, so that its figures match PP's; PP's
  `ClientIndex`, `ClientIRRYield`, `IRR`, `Risk` and `SecurityIndex` were read, not copied:

  - The interval's first day is the reference day: the returns start from its closing value, and
    what happens on it counts no further.
  - Money in and out are deposits and removals, inbound and outbound deliveries, and what crosses
    the filter's edge as `Filter` converts it, each in euros at the ECB rate of its day.
  - TTWROR: each day returns (value + money out) / (previous day's value + money in) − 1, so
    money comes in at the start of the day and goes out at its end; a day with neither value
    before it nor money coming in returns 0. The days are chained.
  - IRR: XIRR of the reference day's value paid in, the money in and out after it including both
    sides of transfers inside, and the last day's value paid out; values of nothing are left out,
    and without any cash flow the IRR is 0. `IRR` solves it as PP does.
  - Drawdown and volatility follow the accumulated TTWROR from the first day with a value; the
    volatility only on trading days.
  - Monthly returns chain the days of each month from the end of the month before.
  - The benchmark's TTWROR is the change of its price in euros over the interval; the shadow
    portfolio buys and sells the benchmark with the money in and out of each day.
  """

  alias Abakus.Depot.Performance.{IRR, TradeCalendar}
  alias Abakus.Depot.Valuation
  alias Abakus.Depot.Valuation.{Filter, Market}

  @enforce_keys [:days, :cash_flows]
  defstruct [:days, :cash_flows]

  @doc """
  Every day of `interval` as `%{date, value, invested_capital, inbound, outbound}` in euro cents,
  and the IRR's cash flows after the reference day as `{date, euros}` with money in negative, in
  order of time.
  """
  def index(
        transactions,
        accounts,
        %Market{} = market,
        %Filter{} = filter,
        %Date.Range{} = interval
      ) do
    flows = flows(transactions, market, filter, interval)
    per_day = Enum.group_by(flows, &elem(&1, 0), &Tuple.delete_at(&1, 0))

    days =
      transactions
      |> Valuation.history(accounts, market, Enum.to_list(interval), filter)
      |> Enum.map(fn point ->
        day_flows = Map.get(per_day, point.date, [])

        %{
          date: point.date,
          value: point.net_worth,
          invested_capital: point.invested_capital,
          inbound: sum(day_flows, :inbound),
          outbound: sum(day_flows, :outbound)
        }
      end)

    cash_flows =
      for {date, kind, cents} <- flows,
          Date.after?(date, interval.first),
          do: {date, if(kind in [:inbound, :transfer_in], do: -cents, else: cents) / 100}

    %__MODULE__{days: days, cash_flows: cash_flows}
  end

  # `{date, kind, cents}` per side of each transaction in the interval, in order of time.
  defp flows(transactions, market, filter, interval) do
    for t <- Enum.sort_by(transactions, & &1.date_time, NaiveDateTime),
        date = NaiveDateTime.to_date(t.date_time),
        date in interval,
        {kind, amount, currency} <- Filter.flows(filter, t),
        do: {date, kind, Market.to_euros(market, amount, currency, date)}
  end

  defp sum(day_flows, kind),
    do: for({^kind, cents} <- day_flows, reduce: 0, do: (sum -> sum + cents))

  @doc "The TTWROR as a fraction, 0.1 for 10 %."
  def ttwror(%__MODULE__{} = index), do: index |> accumulated() |> List.last()

  @doc """
  The TTWROR of every month, year by year, as `%{year, months, total}` in order of time: each
  month's from the last day of the month before, or the reference day, to its last day, or the
  last day of the index; nil for a month without a day after the reference day or after the last
  day, and for one after a total loss, which leaves nothing to return on. `total` chains the
  months of the year. Only the years with a day after the reference day are given.
  """
  def monthly_returns(%__MODULE__{days: days} = index) do
    series = Enum.zip(Enum.map(days, & &1.date), accumulated(index))
    month_ends = Map.new(series, fn {date, accumulated} -> {month(date), accumulated} end)
    months = series |> Enum.drop(1) |> MapSet.new(&month(elem(&1, 0)))
    years = months |> Enum.map(&elem(&1, 0)) |> Enum.uniq() |> Enum.sort()

    for year <- years do
      returns = for month <- 1..12, do: month_return(month_ends, months, {year, month})
      %{year: year, months: returns, total: chain(returns)}
    end
  end

  # From the end of the month before, which is the reference day's 0 before the first month.
  defp month_return(month_ends, months, month) do
    if MapSet.member?(months, month) do
      start = Map.get(month_ends, previous_month(month), 0.0)
      if start + 1 > 0, do: (Map.fetch!(month_ends, month) + 1) / (start + 1) - 1
    end
  end

  defp month(date), do: {date.year, date.month}

  defp previous_month({year, 1}), do: {year - 1, 12}
  defp previous_month({year, month}), do: {year, month - 1}

  @doc "Compounds `returns`, fractions such as 0.1 for 10 %, into one; nil counts as none."
  def chain(returns) do
    returns
    |> Enum.reject(&is_nil/1)
    |> Enum.reduce(1.0, &(&2 * (&1 + 1)))
    |> Kernel.-(1)
  end

  @doc """
  The TTWROR spread over years of 365 days, as PP annualises it; nil after a loss of more than
  everything, which has no such rate.
  """
  def ttwror_per_year(%__MODULE__{days: [reference_day | _] = days} = index) do
    years = Date.diff(List.last(days).date, reference_day.date) / 365
    base = 1 + ttwror(index)
    if base >= 0, do: :math.pow(base, 1 / years) - 1
  end

  @doc """
  The maximum drawdown as PP computes it: the largest fall of the accumulated TTWROR from its
  highest point before, as a fraction, with the day of that point (`from`) and of the low
  (`to`). It starts on the first day with a value; without any fall it is 0 on that day. While
  the highest point is a total loss or below, there is nothing to fall from.
  """
  def drawdown(%__MODULE__{days: days} = index) do
    series = Enum.zip(Enum.map(days, & &1.date), accumulated(index))
    start = Enum.find_index(days, &(&1.value != 0)) || length(days) - 1
    [{first_date, first} | rest] = Enum.drop(series, start)

    initial = %{
      peak: first + 1,
      peak_date: first_date,
      max: 0.0,
      from: first_date,
      to: first_date
    }

    rest
    |> Enum.reduce(initial, fn {date, accumulated}, acc ->
      value = accumulated + 1

      cond do
        value > acc.peak ->
          %{acc | peak: value, peak_date: date}

        acc.peak <= 0 ->
          acc

        (acc.peak - value) / acc.peak > acc.max ->
          %{acc | max: (acc.peak - value) / acc.peak, from: acc.peak_date, to: date}

        true ->
          acc
      end
    end)
    |> Map.take([:max, :from, :to])
  end

  @doc """
  The volatility as PP computes it: the standard deviation of the daily log returns times the
  square root of their number. It leaves out the reference day, days without a value on them or
  the day before, the days markets are closed (`TradeCalendar`) and losses of everything or more,
  which have no log return; with fewer than two returns it is 0.
  """
  def volatility(%__MODULE__{days: days} = index) do
    log_returns =
      for {[previous, day], daily_return} <-
            Enum.zip(Enum.chunk_every(days, 2, 1, :discard), daily_returns(index)),
          previous.value != 0 and day.value != 0,
          TradeCalendar.trading_day?(day.date),
          1 + daily_return > 0,
          do: :math.log(1 + daily_return)

    case length(log_returns) do
      count when count <= 1 ->
        0.0

      count ->
        mean = Enum.sum(log_returns) / count
        squares = Enum.reduce(log_returns, 0.0, fn r, sum -> sum + :math.pow(r - mean, 2) end)
        :math.sqrt(squares / (count - 1) * count)
    end
  end

  # The accumulated TTWROR of every day, 0 on the reference day.
  defp accumulated(index) do
    index
    |> daily_returns()
    |> Enum.scan(0.0, fn daily_return, accumulated ->
      (accumulated + 1) * (daily_return + 1) - 1
    end)
    |> then(&[0.0 | &1])
  end

  # The return of every day after the reference day.
  defp daily_returns(%__MODULE__{days: [reference_day | days]}) do
    days
    |> Enum.map_reduce(reference_day.value, fn day, previous ->
      {daily_return(previous, day), day.value}
    end)
    |> elem(0)
  end

  defp daily_return(previous, %{inbound: inbound}) when previous + inbound == 0, do: 0.0

  defp daily_return(previous, day),
    do: (day.value + day.outbound) / (previous + day.inbound) - 1

  @doc """
  The TTWROR of the benchmark with `security_id` over the interval of `index`, as PP computes a
  benchmark: the change of its price in euros, converted at the ECB rate of each day, from the
  index's first day with a value, or the day before when that is after the reference day, to
  the interval's last day; without any value from the day before the last day, or the reference
  day when that is later. Only from its first price on and up to its last, the latest quote
  included, adding the index's TTWROR up to its first price as PP does. Nil without a price in
  that span.
  """
  def benchmark_ttwror(%__MODULE__{days: days} = index, %Market{} = market, security_id) do
    with {first_price, last_price} <- Market.price_days(market, security_id),
         start = Enum.max([benchmark_start(days), first_price], Date),
         finish = Enum.min([List.last(days).date, last_price], Date),
         false <- Date.before?(finish, start) do
      adjustment = Enum.at(accumulated(index), Date.diff(start, hd(days).date))

      adjustment +
        euro_price(market, security_id, finish) / euro_price(market, security_id, start) - 1
    else
      _no_price -> nil
    end
  end

  defp benchmark_start([reference_day | _] = days) do
    case Enum.find(days, &(&1.value != 0)) do
      nil -> Enum.max([Date.add(List.last(days).date, -1), reference_day.date], Date)
      %{date: date} when date == reference_day.date -> date
      %{date: date} -> Date.add(date, -1)
    end
  end

  @doc """
  The value of the shadow portfolio in the benchmark with `security_id`, in euro cents per day of
  `index` from `first_day` on: on that day it holds the benchmark for the day's value, and the
  money in and out of every later day buys or sells benchmark shares at that day's price in
  euros. It starts with the benchmark's first price when that comes later; empty without one,
  and with a price of 0, which buys no shares.
  """
  def shadow_portfolio(%__MODULE__{days: days}, %Market{} = market, security_id, first_day) do
    with {first_price, _last_price} <- Market.price_days(market, security_id),
         start = Enum.max([first_day, first_price], Date),
         [_ | _] = days <- Enum.drop_while(days, &Date.before?(&1.date, start)),
         prices = Enum.map(days, &euro_price(market, security_id, &1.date)),
         false <- Enum.any?(prices, &(&1 <= 0)) do
      [{first, first_price} | rest] = Enum.zip(days, prices)

      rest
      |> Enum.map_reduce(first.value / first_price, fn {day, price}, shares ->
        shares = shares + (day.inbound - day.outbound) / price
        {{day.date, round(shares * price)}, shares}
      end)
      |> elem(0)
      |> Map.new()
      |> Map.put(first.date, first.value)
    else
      _no_price -> %{}
    end
  end

  defp euro_price(market, security_id, date) do
    price = Market.price(market, security_id, date)
    Market.to_euros(market, price, Market.currency(market, security_id), date)
  end

  @doc "The IRR per year as a fraction, 0.1 for 10 %; nil where PP gets no number."
  def irr(%__MODULE__{days: [reference_day | _] = days, cash_flows: cash_flows}) do
    last_day = List.last(days)

    cash_flows =
      value_flow(reference_day.date, -reference_day.value) ++
        cash_flows ++ value_flow(last_day.date, last_day.value)

    if cash_flows == [], do: 0.0, else: IRR.calculate(cash_flows)
  end

  defp value_flow(_date, 0), do: []
  defp value_flow(date, cents), do: [{date, cents / 100}]
end
