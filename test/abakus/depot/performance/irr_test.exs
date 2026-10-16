defmodule Abakus.Depot.Performance.IRRTest do
  use ExUnit.Case, async: true

  alias Abakus.Depot.Performance.IRR

  test "is the annual rate at which the cash flows are worth nothing today" do
    assert_in_delta IRR.calculate([{~D[2025-01-01], -1_000.0}, {~D[2026-01-01], 1_100.0}]),
                    0.1,
                    1.0e-9

    assert_in_delta IRR.calculate([{~D[2025-01-01], -1_000.0}, {~D[2026-01-01], 900.0}]),
                    -0.1,
                    1.0e-9
  end

  test "counts years of 365 days, as Excel's XIRR" do
    cash_flows = [
      {~D[2008-01-01], -10_000.0},
      {~D[2008-03-01], 2_750.0},
      {~D[2008-10-30], 4_250.0},
      {~D[2009-02-15], 3_250.0},
      {~D[2009-04-01], 2_750.0}
    ]

    assert_in_delta IRR.calculate(cash_flows), 0.373362535, 1.0e-8
  end

  test "annualises a short period" do
    rate = IRR.calculate([{~D[2026-01-01], -1_000.0}, {~D[2026-07-02], 1_050.0}])

    assert_in_delta rate, :math.pow(1.05, 365 / 182) - 1, 1.0e-9
  end

  test "is nil where no rate solves it" do
    assert IRR.calculate([{~D[2025-01-01], 100.0}, {~D[2026-01-01], 100.0}]) == nil
  end
end
