defmodule AbakusWeb.FormatTest do
  use ExUnit.Case, async: true

  alias AbakusWeb.Format

  test "count/1 groups by three with a dot" do
    assert Format.count(0) == "0"
    assert Format.count(842) == "842"
    assert Format.count(1_842) == "1.842"
    assert Format.count(1_000_000) == "1.000.000"
  end

  describe "months" do
    test "names, short names and with the year" do
      assert Format.month_name(~D[2026-03-01]) == "März"
      assert Format.month_short(~D[2026-03-15]) == "Mär"
      assert Format.month_short(~D[2026-10-01]) == "Okt"
      assert Format.month_year(~D[2026-12-31]) == "Dezember 2026"
    end
  end

  describe "dates" do
    test "with and without the year" do
      assert Format.date(~D[2026-03-07]) == "07.03.2026"
      assert Format.day(~D[2026-03-07]) == "07.03."
    end

    test "written out, with and without the year" do
      assert Format.long_date(~D[2027-06-01]) == "1. Juni 2027"
      assert Format.day_month(~D[2026-12-24]) == "24. Dezember"
    end
  end
end
