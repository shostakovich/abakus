defmodule Abakus.FormatTest do
  use ExUnit.Case, async: true

  alias Abakus.{Format, LocalTime}

  describe "dates" do
    test "date/2 writes a date with or without its year, none as a dash" do
      assert Format.date(~D[2026-03-07]) == "07.03.2026"
      assert Format.date(~D[2026-03-07], year: false) == "07.03."
      assert Format.date(~N[2026-10-02 09:05:59]) == "02.10.2026"
      assert Format.date(nil) == "–"
    end

    test "date/2 gives a moment in UTC the date of the host's local time" do
      utc = ~U[2026-10-09 23:30:00.000000Z]

      assert Format.date(utc) == utc |> LocalTime.from_utc() |> Format.date()
    end

    test "long_date/1 writes the month out" do
      assert Format.long_date(~D[2027-06-01]) == "1. Juni 2027"
    end

    test "day_month/1 writes the month out and leaves the year out" do
      assert Format.day_month(~D[2026-12-24]) == "24. Dezember"
    end

    test "long_date_span/2 names its months, its year once when it is in one" do
      assert Format.long_date_span(~D[2026-01-01], ~D[2026-10-07]) ==
               "1. Januar bis 7. Oktober 2026"

      assert Format.long_date_span(~D[2023-10-10], ~D[2026-10-09]) ==
               "10. Oktober 2023 bis 9. Oktober 2026"

      assert Format.long_date_span(~D[2026-03-01], ~D[2026-03-01]) == "1. März 2026"
    end

    test "date_span/3 names its month and year once where they are the same" do
      assert Format.date_span(~D[2026-01-12], ~D[2026-01-28]) == "12.–28.01.2026"
      assert Format.date_span(~D[2026-01-02], ~D[2026-01-28]) == "02.–28.01.2026"
      assert Format.date_span(~D[2026-01-12], ~D[2026-02-03]) == "12.01.–03.02.2026"
      assert Format.date_span(~D[2025-12-12], ~D[2026-01-03]) == "12.12.2025–03.01.2026"
      assert Format.date_span(~D[2026-01-12], ~D[2026-01-12]) == "12.01.2026"
      assert Format.date_span(~D[2026-01-12], ~D[2026-01-28], year: false) == "12.–28.01."
      assert Format.date_span(~D[2026-01-12], ~D[2026-02-03], year: false) == "12.01.–03.02."
    end
  end

  describe "months" do
    test "month_name/1 by number or date" do
      assert Format.month_name(3) == "März"
      assert Format.month_name(~D[2026-12-24]) == "Dezember"
    end

    test "month_abbr/1 by number or date" do
      assert Format.month_abbr(3) == "Mär"
      assert Format.month_abbr(5) == "Mai"
      assert Format.month_abbr(~D[2026-10-01]) == "Okt"
    end

    test "month_year/1" do
      assert Format.month_year(~D[2026-12-31]) == "Dezember 2026"
    end
  end

  describe "times" do
    test "datetime/1 writes a local moment, one in UTC in local time, none as a dash" do
      assert Format.datetime(~N[2026-10-02 09:05:59]) == "02.10.2026, 09:05"

      utc = ~U[2026-10-01 23:30:00.000000Z]
      assert Format.datetime(utc) == Format.datetime(LocalTime.from_utc(utc))
      assert Format.datetime(nil) == "–"
    end

    test "time/1 writes the local time of day of a moment in UTC" do
      utc = ~U[2026-10-01 23:30:00.000000Z]

      assert Format.time(utc) == Calendar.strftime(LocalTime.from_utc(utc), "%H:%M")
    end

    test "recent/1 leaves the date out today" do
      local_now = %{LocalTime.now() | second: 0, microsecond: {0, 6}}
      before = NaiveDateTime.add(local_now, -2, :day)

      assert Format.recent(LocalTime.to_utc(local_now)) ==
               Calendar.strftime(local_now, "%H:%M")

      assert Format.recent(LocalTime.to_utc(before)) ==
               Calendar.strftime(before, "%d.%m. %H:%M")
    end
  end

  describe "numbers" do
    test "number/2 groups by three with a dot and rounds to its places" do
      assert Format.number(0) == "0"
      assert Format.number(842) == "842"
      assert Format.number(1_842) == "1.842"
      assert Format.number(1_000_000) == "1.000.000"
      assert Format.number(Decimal.new("1125"), 2) == "1.125,00"
      assert Format.number(Decimal.new("-17.849"), 1) == "−17,8"
    end

    test "decimal/1 has the places it has" do
      assert Format.decimal(Decimal.new("1.1652")) == "1,1652"
      assert Format.decimal(Decimal.new("161.20")) == "161,2"
      assert Format.decimal(Decimal.new("7843.5")) == "7.843,5"
      assert Format.decimal(Decimal.new("6.2E+3")) == "6.200"
    end

    test "decimal/2 has at least the places given" do
      for {number, places, text} <- [
            {"1234.5678", 0, "1.234,5678"},
            {"0.125", 0, "0,125"},
            {"12.5", 2, "12,50"},
            {"12.500", 0, "12,5"},
            {"-9.99", 2, "−9,99"},
            {"0", 2, "0,00"}
          ] do
        assert Format.decimal(Decimal.new(number), places) == text
      end
    end

    test "shares/1 are shares × 10⁸ with the places they have" do
      assert Format.shares(52_000_000_000) == "520"
      assert Format.shares(620_000_000_000) == "6.200"
      assert Format.shares(9_320_700_000) == "93,207"
      assert Format.shares(12_345_678) == "0,12345678"
      assert Format.shares(-150_000_000_000) == "−1.500"
      assert Format.shares(-150_000_000) == "−1,5"
    end

    test "signed_number/2 leaves out the unit, and the sign of what rounds to zero" do
      assert Format.signed_number(Decimal.new("1.25"), 1) == "+1,3"
      assert Format.signed_number(Decimal.new("-0.384"), 2) == "−0,38"
      assert Format.signed_number(Decimal.new("-0.04"), 1) == "0,0"
    end

    test "percent/2 has one decimal place by default and a % that never wraps" do
      assert Format.percent(Decimal.new("58.07")) == "58,1 %"
      assert Format.percent(Decimal.new("0.04")) == "0,0 %"
      assert Format.percent(Decimal.new("100"), 0) == "100 %"
    end

    test "signed_percent/2 carries its sign and two decimal places by default" do
      assert Format.signed_percent(Decimal.new("0.38")) == "+0,38 %"
      assert Format.signed_percent(Decimal.new("-2.505")) == "−2,51 %"
      assert Format.signed_percent(Decimal.new("1234.5")) == "+1.234,50 %"
      assert Format.signed_percent(Decimal.new("0")) == "0,00 %"
      assert Format.signed_percent(Decimal.new("12.64"), 1) == "+12,6 %"
      assert Format.signed_percent(Decimal.new("-0.04"), 1) == "0,0 %"
    end

    test "signed_rate/2 is a fraction as a change in percent, none a dash" do
      assert Format.signed_rate(0.0038) == "+0,38 %"
      assert Format.signed_rate(-0.123456, 1) == "−12,3 %"
      assert Format.signed_rate(-0.0) == "0,00 %"
      assert Format.signed_rate(nil) == "–"
    end

    test "percent_of/2" do
      assert Format.percent_of(Decimal.new("1"), Decimal.new("8")) == Decimal.new("12.5")
    end
  end
end
