defmodule Abakus.Depot.Dividends do
  @moduledoc """
  The dividends a user received, converted at the ECB rate of the pay date, and those expected in
  the coming months, at the latest rate. Interest does not count. Pure; amounts in euro cents,
  shares and amounts per share × 10⁸.
  """

  alias Abakus.Depot.Distributions
  alias Abakus.Depot.Portfolios.Transaction
  alias Abakus.Depot.Valuation
  alias Abakus.Depot.Valuation.Market

  @doc """
  The dividends of `transactions`, newest first, each with its pay `date`, `security`, `shares`
  (0 where PP booked none), `gross`, `taxes`, `fees` and `net`.
  """
  def received(transactions, %Market{} = market) do
    transactions
    |> Enum.filter(&(&1.type == :dividend))
    |> Enum.sort_by(& &1.date_time, {:desc, NaiveDateTime})
    |> Enum.map(&dividend(&1, market))
  end

  defp dividend(%Transaction{currency: currency} = t, market) do
    date = NaiveDateTime.to_date(t.date_time)
    euros = &Market.to_euros(market, &1, currency, date)

    %{
      date: date,
      security: Market.security(market, t.security_id),
      shares: t.shares || 0,
      gross: euros.(Valuation.gross_value(t, currency)),
      taxes: euros.(units(t, :tax)),
      fees: euros.(units(t, :fee)),
      net: euros.(t.amount)
    }
  end

  defp units(t, type), do: t.units |> Enum.filter(&(&1.type == type)) |> Enum.sum_by(& &1.amount)

  @doc """
  The dividends of `received` per year, newest first, from the first dividend's year to today's,
  each with its twelve `months`; every total as `gross` and `net`.
  """
  def by_year([], _today), do: []

  def by_year(received, %Date{} = today) do
    first = received |> Enum.map(& &1.date.year) |> Enum.min()
    last = received |> Enum.map(& &1.date.year) |> Enum.max() |> max(today.year)
    per_month = Enum.group_by(received, &{&1.date.year, &1.date.month})

    for year <- last..first//-1 do
      months = for month <- 1..12, do: total(Map.get(per_month, {year, month}, []))
      Map.merge(%{year: year, months: months}, total(months))
    end
  end

  def total(received, %Date.Range{} = range),
    do: received |> Enum.filter(&(&1.date in range)) |> total()

  def total(dividends),
    do: %{gross: Enum.sum_by(dividends, & &1.gross), net: Enum.sum_by(dividends, & &1.net)}

  @doc """
  The dividends expected after `today` up to the end of the eleventh month after today's, by pay
  date, from the DivvyDiary dividends `stored`; `market` needs the rates up to `today`.

  - `kind: :announced`: a stored dividend paid after today, for the shares held at the end of its
    ex date, or today's when that is still to come or unknown
  - `kind: :forecast`: a stored dividend of the last 12 months one year later, for today's
    shares, only after the month of the security's last stored one. Without stored dividends the
    user's own distributions stand in.

  Each has `security`, `ex_date` (may be nil), `pay_date`, `shares`, `per_share` in `currency`,
  `gross` and `net`: the gross times the security's net-to-gross ratio of the last 12 months, or
  the gross with `net_is_gross` set. `received` (as `received/2` gives it) saves computing that.
  """
  def upcoming(transactions, stored, %Market{} = market, %Date{} = today, received \\ nil) do
    held = shares_by_security(transactions, today)
    announced = Enum.filter(stored, &Date.after?(&1.pay_date, today))
    ratios = net_ratios(received || received_last_12_months(transactions, market, today), today)
    months = coming_months(today)

    (announced(announced, transactions, held, today) ++
       forecast(stored, transactions, held, market, today))
    |> Enum.filter(&(&1.pay_date in months))
    |> Enum.map(&with_amounts(&1, market, ratios, today))
    |> Enum.sort_by(&{Date.to_gregorian_days(&1.pay_date), &1.security.name})
  end

  @doc """
  The `announced` and `forecast` totals of `upcoming` for today's month and the next eleven, each
  `month` as its first day.
  """
  def by_coming_month(upcoming, %Date{} = today) do
    first = Date.beginning_of_month(today)
    by_month = Enum.group_by(upcoming, &Date.beginning_of_month(&1.pay_date))

    for offset <- 0..11 do
      month = Date.shift(first, month: offset)
      dividends = Map.get(by_month, month, [])
      {announced, forecast} = Enum.split_with(dividends, &(&1.kind == :announced))
      %{month: month, announced: total(announced), forecast: total(forecast)}
    end
  end

  defp coming_months(today),
    do: Date.range(Date.add(today, 1), today |> Date.shift(month: 11) |> Date.end_of_month())

  defp last_12_months(today), do: Date.range(today |> Date.shift(year: -1) |> Date.add(1), today)

  defp announced(announced, transactions, held, today) do
    held_on =
      announced
      |> Enum.map(& &1.ex_date)
      |> Enum.reject(&(is_nil(&1) or Date.after?(&1, today)))
      |> Enum.uniq()
      |> Map.new(&{&1, shares_by_security(transactions, &1)})

    for dividend <- announced,
        shares = shares_on_ex_date(dividend, held_on, held),
        shares > 0 do
      %{
        kind: :announced,
        security_id: dividend.security_id,
        ex_date: dividend.ex_date,
        pay_date: dividend.pay_date,
        per_share: dividend.per_share,
        currency: dividend.currency,
        shares: shares
      }
    end
  end

  defp shares_on_ex_date(dividend, held_on, held),
    do: held_on |> Map.get(dividend.ex_date, held) |> Map.get(dividend.security_id, 0)

  defp forecast(stored, transactions, held, market, today) do
    stored = Enum.group_by(stored, & &1.security_id)

    for {security_id, shares} <- held,
        known = known_dividends(security_id, stored, transactions, market),
        last = known |> Enum.map(& &1.pay_date) |> Enum.max(Date, fn -> nil end),
        paid <- known,
        paid.per_share != nil and not Date.after?(paid.pay_date, today),
        pay_date = Date.shift(paid.pay_date, year: 1),
        Date.after?(pay_date, Date.end_of_month(last)) do
      %{
        kind: :forecast,
        security_id: security_id,
        ex_date: paid.ex_date && Date.shift(paid.ex_date, year: 1),
        pay_date: pay_date,
        per_share: paid.per_share,
        currency: paid.currency,
        shares: shares
      }
    end
  end

  defp known_dividends(security_id, stored, transactions, market) do
    case Map.fetch(stored, security_id) do
      {:ok, dividends} ->
        dividends

      :error ->
        for distribution <- own_distributions(security_id, transactions, market),
            do: Map.put(distribution, :pay_date, distribution.date)
    end
  end

  defp own_distributions(security_id, transactions, market) do
    Distributions.of(
      Market.security(market, security_id),
      Enum.filter(transactions, &(&1.security_id == security_id)),
      market
    )
  end

  defp shares_by_security(transactions, date) do
    transactions
    |> Valuation.holdings(date)
    |> Enum.group_by(& &1.security_id, & &1.shares)
    |> Map.new(fn {security_id, shares} -> {security_id, Enum.sum(shares)} end)
    |> Map.reject(fn {_security_id, shares} -> shares <= 0 end)
  end

  defp net_ratios(received, today) do
    received
    |> Enum.filter(&(&1.date in last_12_months(today) and &1.security != nil))
    |> Enum.group_by(& &1.security.id)
    |> Map.new(fn {security_id, dividends} ->
      {security_id, {Enum.sum_by(dividends, & &1.net), Enum.sum_by(dividends, & &1.gross)}}
    end)
    |> Map.reject(fn {_security_id, {_net, gross}} -> gross <= 0 end)
  end

  defp received_last_12_months(transactions, market, today) do
    transactions
    |> Enum.filter(&(NaiveDateTime.to_date(&1.date_time) in last_12_months(today)))
    |> received(market)
  end

  defp with_amounts(dividend, market, ratios, today) do
    in_currency = per_share_times_shares(dividend.per_share, dividend.shares)
    gross = Market.to_euros(market, in_currency, dividend.currency, today)
    ratio = ratios[dividend.security_id]

    dividend
    |> Map.delete(:security_id)
    |> Map.merge(%{
      security: Market.security(market, dividend.security_id),
      gross: gross,
      net: net(gross, ratio),
      net_is_gross: ratio == nil
    })
  end

  defp net(gross, nil), do: gross

  defp net(gross, {net, ratio_gross}),
    do: gross |> Decimal.mult(net) |> Decimal.div(ratio_gross) |> round_cents()

  defp per_share_times_shares(per_share, shares),
    do: per_share |> Decimal.mult(shares) |> Decimal.div(100_000_000_000_000) |> round_cents()

  defp round_cents(decimal), do: decimal |> Decimal.round(0, :half_even) |> Decimal.to_integer()
end
