defmodule Abakus.Depot.PeriodTest do
  use ExUnit.Case, async: true

  alias Abakus.Depot.Period

  @today ~D[2026-10-09]
  @long_ago ~D[2020-01-01]

  describe "range/3" do
    for {period, first} <- [
          one_month: ~D[2026-09-09],
          six_months: ~D[2026-04-09],
          year_to_date: ~D[2026-01-01],
          one_year: ~D[2025-10-09],
          three_years: ~D[2023-10-09],
          five_years: ~D[2021-10-09],
          max: @long_ago
        ] do
      test "#{period} starts on #{first}" do
        assert Period.range(unquote(period), @today, @long_ago) ==
                 Date.range(unquote(Macro.escape(first)), @today)
      end
    end

    test "starts no earlier than the first transaction" do
      assert Period.range(:one_year, @today, ~D[2026-08-01]) == Date.range(~D[2026-08-01], @today)
    end

    test "is only today without a transaction up to today" do
      assert Period.range(:max, @today, nil) == Date.range(@today, @today)
      assert Period.range(:six_months, @today, Date.add(@today, 1)) == Date.range(@today, @today)
    end
  end

  describe "interval/3" do
    for {period, reference_day} <- [
          one_month: ~D[2026-09-09],
          six_months: ~D[2026-04-09],
          year_to_date: ~D[2025-12-31],
          one_year: ~D[2025-10-09],
          three_years: ~D[2023-10-09],
          max: ~D[2019-12-31]
        ] do
      test "#{period} starts from the close of #{reference_day}" do
        assert Period.interval(unquote(period), @today, @long_ago) ==
                 Date.range(unquote(Macro.escape(reference_day)), @today)
      end
    end

    test "starts no earlier than the day before the first transaction" do
      assert Period.interval(:one_year, @today, ~D[2026-08-01]) ==
               Date.range(~D[2026-07-31], @today)
    end

    test "starts yesterday without a transaction up to today" do
      assert Period.interval(:max, @today, nil) == Date.range(~D[2026-10-08], @today)

      assert Period.interval(:year_to_date, @today, Date.add(@today, 1)) ==
               Date.range(~D[2026-10-08], @today)
    end
  end

  describe "chart_days/1" do
    test "are all days of up to a year" do
      range = Date.range(~D[2025-10-09], @today)

      assert Period.chart_days(range) == Enum.to_list(range)
    end

    test "are the first day and every seventh counting back from the last beyond a year" do
      days = Period.chart_days(Date.range(~D[2025-10-01], @today))

      assert hd(days) == ~D[2025-10-01]
      assert Enum.at(days, 1) == ~D[2025-10-03]
      assert List.last(days) == @today
      assert days |> tl() |> Enum.chunk_every(2, 1, :discard) |> Enum.all?(&week_apart?/1)
    end
  end

  defp week_apart?([day, next]), do: Date.diff(next, day) == 7
end
