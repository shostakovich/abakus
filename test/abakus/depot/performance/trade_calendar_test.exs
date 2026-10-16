defmodule Abakus.Depot.Performance.TradeCalendarTest do
  use ExUnit.Case, async: true

  alias Abakus.Depot.Performance.TradeCalendar

  test "trades on weekdays" do
    assert TradeCalendar.trading_day?(~D[2026-10-09])
    refute TradeCalendar.trading_day?(~D[2026-10-10])
    refute TradeCalendar.trading_day?(~D[2026-10-11])
  end

  test "closes on PP's default holidays" do
    for date <- [
          ~D[2026-01-01],
          ~D[2026-04-03],
          ~D[2026-04-06],
          ~D[2026-05-01],
          ~D[2026-12-24],
          ~D[2026-12-25],
          ~D[2025-12-26],
          ~D[2024-03-29],
          ~D[2024-04-01]
        ],
        do: refute(TradeCalendar.trading_day?(date), "#{date} is a holiday")
  end

  test "trades on other public holidays" do
    assert TradeCalendar.trading_day?(~D[2026-10-05])
    assert TradeCalendar.trading_day?(~D[2026-05-14])
    assert TradeCalendar.trading_day?(~D[2026-12-31])
  end
end
