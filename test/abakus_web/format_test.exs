defmodule AbakusWeb.FormatTest do
  use ExUnit.Case, async: true

  alias AbakusWeb.Format

  describe "amount/1 and euros/1" do
    test "German digits with a real minus sign" do
      assert Format.amount(0) == "0,00"
      assert Format.amount(5) == "0,05"
      assert Format.amount(123_456) == "1.234,56"
      assert Format.amount(-105_000) == "−1.050,00"
      assert Format.amount(100_000_000_000) == "1.000.000.000,00"
      assert Format.euros(-999) == "−9,99 €"
    end

    test "signed_euros/1 marks inflows with a plus" do
      assert Format.signed_euros(4_875) == "+48,75 €"
      assert Format.signed_euros(-4_875) == "−48,75 €"
      assert Format.signed_euros(0) == "0,00 €"
    end
  end

  test "count/1 groups by three with a dot" do
    assert Format.count(0) == "0"
    assert Format.count(842) == "842"
    assert Format.count(1_842) == "1.842"
    assert Format.count(1_000_000) == "1.000.000"
  end

  describe "parse_amount/1" do
    test "reads German and plain amounts into cents" do
      for {text, cents} <- [
            {"250,5", 25_050},
            {"1.050", 105_000},
            {"1.234,56", 123_456},
            {"12.5", 1_250},
            {"12.50", 1_250},
            {" 12 € ", 1_200},
            {"−5", -500},
            {"-0,99", -99},
            {"+3", 300},
            {",5", 50},
            {"12,", 1_200},
            {"12.", 1_200},
            {"", 0},
            {"  ", 0}
          ],
          do: assert(Format.parse_amount(text) == {:ok, cents}, text)
    end

    test "refuses what is no amount of whole cents" do
      for text <- [
            "zwölf",
            "1,234.56",
            "12,345",
            "1..2",
            "--1",
            "1-",
            ",",
            String.duplicate("9", 31)
          ],
          do: assert(Format.parse_amount(text) == :error, text)
    end
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

    test "the browser's date when it is a plausible one" do
      assert Format.today("2026-03-07") == ~D[2026-03-07]
      assert Format.today("1999-12-31") == Date.utc_today()
      assert Format.today("07.03.2026") == Date.utc_today()
      assert Format.today(nil) == Date.utc_today()
    end
  end
end
