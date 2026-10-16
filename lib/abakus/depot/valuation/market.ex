defmodule Abakus.Depot.Valuation.Market do
  @moduledoc """
  Closing prices, latest quotes and ECB rates for valuing holdings, looked up as PP does. Pure;
  the contexts load what it holds. Prices × 10⁸, amounts in cents.
  """

  alias Abakus.Depot.Securities.Security

  defstruct securities: %{}, closes: %{}, rates: %{}

  @doc """
  Builds a market from securities with their latest quote, closes as `{security_id, date, close}`
  and ECB rates as `{currency, date, rate}`.
  """
  def new(securities, closes, rates) do
    %__MODULE__{
      securities: Map.new(securities, &{&1.id, &1}),
      closes: series(closes),
      rates: series(rates)
    }
  end

  # Per key a tuple of `{date, value}` in order of date, for a binary search.
  defp series(rows) do
    rows
    |> Enum.group_by(&elem(&1, 0), &{elem(&1, 1), elem(&1, 2)})
    |> Map.new(fn {key, series} ->
      {key, series |> Enum.sort_by(&elem(&1, 0), Date) |> List.to_tuple()}
    end)
  end

  def security(%__MODULE__{securities: securities}, security_id), do: securities[security_id]

  def currency(market, security_id), do: security(market, security_id).currency

  @doc """
  The price of a security on `date`, as PP takes it: the latest quote from its day on unless a
  close is newer, else the close of the day or the last one before it, or the first close for an
  earlier day. Nil without any price.
  """
  def price(%__MODULE__{} = market, security_id, date) do
    closes = Map.get(market.closes, security_id, {})
    quote = latest_quote(market.securities[security_id])

    if quote_applies?(quote, closes, date), do: elem(quote, 1), else: on(closes, date)
  end

  @doc """
  The first and the last day with a price of a security as `{first, last}`, its latest quote
  among them, as PP lists a security's prices; nil without any price.
  """
  def price_days(%__MODULE__{} = market, security_id) do
    closes = Map.get(market.closes, security_id, {})

    close_days =
      if closes == {},
        do: [],
        else: [elem(elem(closes, 0), 0), elem(elem(closes, tuple_size(closes) - 1), 0)]

    quote_days =
      market.securities[security_id] |> latest_quote() |> List.wrap() |> Enum.map(&elem(&1, 0))

    case close_days ++ quote_days do
      [] -> nil
      days -> {Enum.min(days, Date), Enum.max(days, Date)}
    end
  end

  defp latest_quote(%Security{latest_date: %Date{} = date, latest_close: close})
       when is_integer(close),
       do: {date, close}

  defp latest_quote(_security), do: nil

  defp quote_applies?(nil, _closes, _date), do: false
  defp quote_applies?(_quote, {} = _closes, _date), do: true

  defp quote_applies?({quote_date, _close}, closes, date) do
    {last_close_date, _last_close} = elem(closes, tuple_size(closes) - 1)
    not Date.before?(date, quote_date) and not Date.before?(quote_date, last_close_date)
  end

  # Pence, agorot and cents, with their main currency.
  @subunits %{"GBX" => "GBP", "ILA" => "ILS", "ZAC" => "ZAR"}

  @doc "The currencies whose ECB rates `to_euros/4` needs to convert `currencies`."
  def rate_currencies(currencies),
    do: currencies |> Enum.flat_map(&[&1 | List.wrap(@subunits[&1])]) |> Enum.uniq()

  @doc """
  Converts an amount in `currency` to euro cents at the ECB rate on `date` as PP does: with the
  inverse rate to ten places, rounded half down, and pence, agorot and cents at a hundredth of
  their main currency's; without any rate, it stays as it is.
  """
  def to_euros(_market, amount, "EUR", _date), do: amount

  def to_euros(%__MODULE__{rates: rates}, amount, currency, date) do
    case euro_rate(rates, currency, date) do
      nil -> amount
      rate -> rate |> Decimal.mult(amount) |> Decimal.round(0, :half_down) |> Decimal.to_integer()
    end
  end

  defp euro_rate(rates, currency, date) when is_map_key(@subunits, currency) do
    case euro_rate(rates, @subunits[currency], date) do
      nil -> nil
      rate -> Decimal.mult(rate, Decimal.new("0.01"))
    end
  end

  defp euro_rate(rates, currency, date) do
    case on(Map.get(rates, currency, {}), date) do
      nil -> nil
      rate -> Decimal.new(1) |> Decimal.div(rate) |> Decimal.round(10, :half_down)
    end
  end

  # The value on `date` or the last one before it; the first one for an earlier day, as in PP.
  defp on({}, _date), do: nil

  defp on(series, date) do
    {_day, value} = elem(series, last_on_or_before(series, date, 0, tuple_size(series) - 1))
    value
  end

  defp last_on_or_before(series, date, low, high) when low < high do
    middle = div(low + high + 1, 2)
    {day, _value} = elem(series, middle)

    if Date.after?(day, date),
      do: last_on_or_before(series, date, low, middle - 1),
      else: last_on_or_before(series, date, middle, high)
  end

  defp last_on_or_before(_series, _date, low, _high), do: low
end
