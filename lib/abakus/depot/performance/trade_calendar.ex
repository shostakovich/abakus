defmodule Abakus.Depot.Performance.TradeCalendar do
  @moduledoc """
  The days markets trade on as PP's default trade calendar has them (read, not copied): every
  weekday but New Year's Day, Good Friday, Easter Monday, Labour Day and 24 to 26 December.
  """

  @doc "Whether markets trade on `date`."
  def trading_day?(%Date{} = date),
    do: Date.day_of_week(date) <= 5 and date not in holidays(date.year)

  defp holidays(year) do
    easter = easter_sunday(year)

    [
      Date.new!(year, 1, 1),
      Date.add(easter, -2),
      Date.add(easter, 1),
      Date.new!(year, 5, 1),
      Date.new!(year, 12, 24),
      Date.new!(year, 12, 25),
      Date.new!(year, 12, 26)
    ]
  end

  # The Gregorian computus after Meeus, Jones and Butcher.
  defp easter_sunday(year) do
    a = rem(year, 19)
    b = div(year, 100)
    c = rem(year, 100)
    d = div(b, 4)
    e = rem(b, 4)
    f = div(b + 8, 25)
    g = div(b - f + 1, 3)
    h = rem(19 * a + b - d - g + 15, 30)
    i = div(c, 4)
    k = rem(c, 4)
    l = rem(32 + 2 * e + 2 * i - h - k, 7)
    m = div(a + 11 * h + 22 * l, 451)
    month = div(h + l - 7 * m + 114, 31)
    day = rem(h + l - 7 * m + 114, 31) + 1

    Date.new!(year, month, day)
  end
end
