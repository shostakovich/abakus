defmodule AbakusWeb.Depot.Format do
  @moduledoc """
  German formats for prices, shares, percentages, dates and times; times in the host's local
  time. Amounts in euros are `Abakus.Money`'s.
  """

  alias Abakus.Depot.Portfolios.Portfolio
  alias Abakus.LocalTime

  @doc """
  A price × 10⁸ with two to four decimal places and its currency as `currency/1` names it, e.g.
  `1.234,5678 USD` or `166,66 €`; the currency never wraps onto a line of its own.
  """
  def price(nil, _currency), do: "–"
  def price(close, currency), do: price(close, currency, price_places(close))

  @doc "A price × 10⁸ with `places` decimal places."
  def price(nil, _currency, _places), do: "–"

  def price(close, currency, places) do
    [whole, fraction] =
      close
      |> price_amount()
      |> Decimal.round(places)
      |> Decimal.to_string(:normal)
      |> String.split(".")

    [group_thousands(whole) <> "," <> fraction, currency(currency)]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join("\u00A0")
  end

  @doc "The decimal places a price × 10⁸ shows: those it has, from two to four."
  def price_places(close), do: -Decimal.normalize(price_amount(close)).exp |> max(2) |> min(4)

  defp price_amount(close),
    do: close |> Decimal.new() |> Decimal.div(100_000_000) |> Decimal.round(4)

  @month_names ~w(Januar Februar März April Mai Juni Juli August September Oktober November Dezember)
  @month_abbrs ~w(Jan Feb Mär Apr Mai Jun Jul Aug Sep Okt Nov Dez)

  @doc "The name of a month, by its number or a date in it, e.g. `März`."
  def month_name(%{month: month}), do: month_name(month)
  def month_name(month) when month in 1..12, do: Enum.at(@month_names, month - 1)

  @doc "The abbreviation of a month, by its number or a date in it, e.g. `Mär`."
  def month_abbr(%{month: month}), do: month_abbr(month)
  def month_abbr(month) when month in 1..12, do: Enum.at(@month_abbrs, month - 1)

  @doc "A currency as prices name it: `€` for euros, otherwise its code."
  def currency("EUR"), do: "€"
  def currency(code), do: code

  @doc "How setzkasten's `<.amount>` names a currency, as `currency/1` does."
  def currency_display("EUR"), do: :symbol
  def currency_display(_code), do: :code

  @doc "A change of a price × 10⁸ with its sign, e.g. `−1,06 €`; none when it rounds to zero."
  def signed_price(change, currency) do
    unchanged = price(0, currency)

    case price(abs(change), currency) do
      ^unchanged -> unchanged
      shown when change > 0 -> "+" <> shown
      shown -> "−" <> shown
    end
  end

  @doc "Shares × 10⁸ with as many decimal places as they have, e.g. `6.200` or `93,207`."
  def shares(shares) do
    shares = shares |> Decimal.div(100_000_000) |> Decimal.normalize()
    number(shares, max(-shares.exp, 0), "")
  end

  @doc "A decimal in German notation with `places` decimal places, e.g. `1.125,00`."
  def decimal(%Decimal{} = decimal, places), do: number(decimal, places, "")

  @doc "A share of a total in percent, e.g. `58,1 %`; the % never wraps onto a line of its own."
  def percent(%Decimal{} = percent, places \\ 1), do: number(percent, places, "") <> "\u00A0%"

  @doc """
  A fund size in cents in billions with one decimal place, e.g. `17,8 Mrd. €`, below 100 million
  in whole millions, e.g. `85 Mio. €`; it never wraps.
  """
  def fund_size(nil, _currency), do: "–"

  def fund_size(cents, currency) do
    amount =
      if cents >= 10_000_000_000,
        do: number(Decimal.div(cents, 100_000_000_000), 1, "") <> "\u00A0Mrd.",
        else: number(Decimal.div(cents, 100_000_000), 0, "") <> "\u00A0Mio."

    amount <> "\u00A0" <> currency(currency)
  end

  @doc "A TER, a fraction, in percent with two decimal places, e.g. `0,22 %`."
  def ter(nil), do: "–"
  def ter(%Decimal{} = ter), do: ter |> Decimal.mult(100) |> percent(2)

  @doc "A decimal with the places it has, e.g. an exchange rate `1,1652` or `93,207` shares."
  def rate(%Decimal{} = rate) do
    rate = Decimal.normalize(rate)
    number(rate, max(-rate.exp, 0), "")
  end

  @doc """
  A change in percent with its sign and two or `places` decimal places, e.g. `+0,38 %`; the %
  never wraps onto a line of its own.
  """
  def signed_percent(%Decimal{} = percent, places \\ 2),
    do: signed_number(percent, places) <> "\u00A0%"

  @doc """
  A rate, a fraction such as 0.0038, as a change in percent with its sign, e.g. `+0,38 %`; `–`
  for none.
  """
  def signed_rate(rate, places \\ 2)
  def signed_rate(nil, _places), do: "–"
  def signed_rate(rate, places), do: Decimal.from_float(rate * 100) |> signed_percent(places)

  @doc "A number with its sign and `places` decimal places, e.g. `+1,2` or `−0,38`."
  def signed_number(%Decimal{} = number, places), do: number(number, places, "+")

  @doc "`part` in percent of `whole`, for `percent/2` and `signed_percent/2`."
  def percent_of(part, whole), do: part |> Decimal.mult(100) |> Decimal.div(whole)

  # German notation with a real minus sign; `plus` goes before a positive number.
  defp number(decimal, places, plus) do
    rounded = Decimal.round(decimal, places)

    sign =
      cond do
        Decimal.positive?(rounded) -> plus
        Decimal.negative?(rounded) -> "−"
        true -> ""
      end

    [whole | fraction] =
      rounded |> Decimal.abs() |> Decimal.to_string(:normal) |> String.split(".")

    sign <> group_thousands(whole) <> Enum.map_join(fraction, &("," <> &1))
  end

  defp group_thousands("-" <> digits), do: "-" <> group_thousands(digits)

  defp group_thousands(digits) do
    digits
    |> String.graphemes()
    |> Enum.reverse()
    |> Enum.chunk_every(3)
    |> Enum.map(&Enum.reverse/1)
    |> Enum.reverse()
    |> Enum.map_join(".", &Enum.join/1)
  end

  @doc "A portfolio's name or its `name`; „Ohne Namen“ for the empty one PP may store."
  def portfolio_name(%{name: name}), do: portfolio_name(name)
  def portfolio_name(name) when name in [nil, ""], do: "Ohne Namen"
  def portfolio_name(name) when is_binary(name), do: name

  @doc "A depot or account number by its last four digits, e.g. „…4471“."
  def masked(number),
    do: "…" <> (number |> Portfolio.digits() |> String.slice(-4, 4))

  @doc "A day without its year, e.g. `14.03.`."
  def short_date(nil), do: "–"
  def short_date(%Date{} = date), do: Calendar.strftime(date, "%d.%m.")

  def date(nil), do: "–"
  def date(%Date{} = date), do: Calendar.strftime(date, "%d.%m.%Y")

  def date(%DateTime{} = utc),
    do: utc |> LocalTime.from_utc() |> NaiveDateTime.to_date() |> date()

  @doc "The days from `first` to `last`, e.g. `1. Januar bis 7. Oktober 2026`."
  def days(day, day), do: long_date(day)

  def days(%Date{year: year} = first, %Date{year: year} = last),
    do: "#{first.day}. #{month_name(first)} bis #{long_date(last)}"

  def days(first, last), do: "#{long_date(first)} bis #{long_date(last)}"

  @doc """
  The days from `first` to `last` in short, e.g. `12.–28.01.2026`, `12.01.–03.02.2026` or
  `12.12.2025–03.01.2026`; without the year, e.g. `12.–28.01.`, when `year?` is false.
  """
  def date_span(first, last, year? \\ true)

  def date_span(day, day, year?), do: span_end(day, year?)

  def date_span(
        %Date{year: year, month: month} = first,
        %Date{year: year, month: month} = last,
        year?
      ),
      do: Calendar.strftime(first, "%d.–") <> span_end(last, year?)

  def date_span(%Date{year: year} = first, %Date{year: year} = last, year?),
    do: Calendar.strftime(first, "%d.%m.–") <> span_end(last, year?)

  def date_span(first, last, _year?), do: date(first) <> "–" <> date(last)

  defp span_end(date, true), do: date(date)
  defp span_end(date, false), do: short_date(date)

  defp long_date(date), do: "#{date.day}. #{month_name(date)} #{date.year}"

  @doc "A recent time in local time, e.g. `17:30` today and `09.10. 17:30` before."
  def recent(%DateTime{} = utc) do
    local = LocalTime.from_utc(utc)

    if NaiveDateTime.to_date(local) == LocalTime.today(),
      do: Calendar.strftime(local, "%H:%M"),
      else: Calendar.strftime(local, "%d.%m. %H:%M")
  end

  def datetime(nil), do: "–"

  def datetime(%DateTime{} = utc),
    do: utc |> LocalTime.from_utc() |> Calendar.strftime("%d.%m.%Y, %H:%M")
end
