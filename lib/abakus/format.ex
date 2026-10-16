defmodule Abakus.Format do
  @moduledoc """
  Dates, times and numbers as the German UI and messages write them, in every area: `"07.03.2026"`,
  `"1. Juni 2027"`, `"1.842"`, `"+0,38 %"`. Built on `Setzkasten.Format`; moments are shown in
  the host's local time (`Abakus.LocalTime`). Amounts are `Abakus.Money`'s.
  """

  alias Abakus.LocalTime
  alias Setzkasten.Format

  @none "–"
  @nbsp "\u00A0"
  @month_names ~w(Januar Februar März April Mai Juni Juli August September Oktober November Dezember)
  @month_abbrs ~w(Jan Feb Mär Apr Mai Jun Jul Aug Sep Okt Nov Dez)

  @doc """
  A date, `"07.03.2026"`, or with `year: false` `"07.03."`; a moment in UTC gives its local date,
  `nil` a dash. Options are `Setzkasten.Format.date/2`'s.
  """
  def date(value, opts \\ [])
  def date(nil, _opts), do: @none
  def date(%DateTime{} = utc, opts), do: utc |> LocalTime.date() |> Format.date(opts)
  def date(value, opts), do: Format.date(value, opts)

  @doc ~s(A date written out: `"1. Juni 2027"`.)
  def long_date(%Date{year: year} = date), do: "#{day_month(date)} #{year}"

  @doc ~s(A date written out without its year: `"24. Dezember"`.)
  def day_month(%Date{day: day} = date), do: "#{day}. #{month_name(date)}"

  @doc ~s(The name of a month, by its number or a date in it: `"März"`.)
  def month_name(%{month: month}), do: month_name(month)
  def month_name(month) when month in 1..12, do: Enum.at(@month_names, month - 1)

  @doc ~s(The abbreviation of a month, by its number or a date in it: `"Mär"`.)
  def month_abbr(%{month: month}), do: month_abbr(month)
  def month_abbr(month) when month in 1..12, do: Enum.at(@month_abbrs, month - 1)

  @doc ~s(A month with its year: `"Dezember 2026"`.)
  def month_year(%{year: year} = date), do: "#{month_name(date)} #{year}"

  @doc """
  The days from `first` to `last` written out, the year once when it is the same:
  `"1. Januar bis 7. Oktober 2026"`.
  """
  def long_date_span(day, day), do: long_date(day)

  def long_date_span(%Date{year: year} = first, %Date{year: year} = last),
    do: "#{day_month(first)} bis #{long_date(last)}"

  def long_date_span(first, last), do: "#{long_date(first)} bis #{long_date(last)}"

  @doc """
  The days from `first` to `last` in short, month and year once where they are the same:
  `"12.–28.01.2026"`, `"12.01.–03.02.2026"`, `"12.12.2025–03.01.2026"`; `year: false` leaves the
  year out of the end, `"12.–28.01."`.
  """
  def date_span(first, last, opts \\ [])

  def date_span(day, day, opts), do: date(day, opts)

  def date_span(
        %Date{year: year, month: month} = first,
        %Date{year: year, month: month} = last,
        opts
      ),
      do: String.pad_leading("#{first.day}", 2, "0") <> ".–" <> date(last, opts)

  def date_span(%Date{year: year} = first, %Date{year: year} = last, opts),
    do: date(first, year: false) <> "–" <> date(last, opts)

  def date_span(first, last, _opts), do: date(first) <> "–" <> date(last)

  @doc ~s(A moment in local time, `"02.10.2026, 14:05"`, from UTC or already local; `nil` a dash.)
  def datetime(nil), do: @none
  def datetime(%DateTime{} = utc), do: utc |> LocalTime.from_utc() |> datetime()
  def datetime(%NaiveDateTime{} = local), do: Format.datetime(local)

  @doc ~s(The local time of day of a moment in UTC: `"17:30"`.)
  def time(%DateTime{} = utc), do: utc |> LocalTime.from_utc() |> Format.time()

  @doc ~s(A recent moment in local time: `"17:30"` today, `"09.10. 17:30"` before.)
  def recent(%DateTime{} = utc) do
    local = LocalTime.from_utc(utc)

    if NaiveDateTime.to_date(local) == LocalTime.today(),
      do: Format.time(local),
      else: Format.date(local, year: false) <> " " <> Format.time(local)
  end

  @doc ~s(A number with `places` decimal places and a dot between groups of three: `"1.842"`, `"−1.125,00"`.)
  def number(value, places \\ 0), do: Format.number(value, decimals: places)

  @doc """
  A decimal with the places it has, at least `places`: an exchange rate `"1,1652"`, `"7.843,5"`;
  a Depot field holds its numbers so, `"12,50"`.
  """
  def decimal(%Decimal{} = decimal, places \\ 0) do
    normalized = Decimal.normalize(decimal)
    number(normalized, max(-normalized.exp, places))
  end

  @doc ~s(Shares × 10⁸ with the places they have: `"6.200"`, `"93,207"`.)
  def shares(shares), do: shares |> Decimal.div(100_000_000) |> decimal()

  @doc ~s(A number with its sign and `places` decimal places, none when it rounds to zero: `"+1,3"`, `"−0,38"`.)
  def signed_number(value, places), do: Format.number(value, decimals: places, signed: true)

  @doc ~s(A percentage with one or `places` decimal places: `"58,1 %"`; the % never wraps.)
  def percent(value, places \\ 1), do: number(value, places) <> @nbsp <> "%"

  @doc ~s(A change in percent with its sign and two or `places` decimal places: `"+0,38 %"`.)
  def signed_percent(value, places \\ 2), do: signed_number(value, places) <> @nbsp <> "%"

  @doc ~s(A rate, a fraction such as 0.0038, as a change in percent: `"+0,38 %"`; `nil` a dash.)
  def signed_rate(rate, places \\ 2)
  def signed_rate(nil, _places), do: @none
  def signed_rate(rate, places), do: Decimal.from_float(rate * 100) |> signed_percent(places)

  @doc "`part` in percent of `whole`, for `percent/2` and `signed_percent/2`."
  def percent_of(part, whole), do: part |> Decimal.mult(100) |> Decimal.div(whole)
end
