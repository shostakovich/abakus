defmodule Abakus.Depot.Receipts.MatchingTest do
  use ExUnit.Case, async: true

  import Abakus.Depot.ReceiptsFixtures

  alias Abakus.Depot.Receipts.{Fields, Matching}

  defp fields(changes \\ %{}) do
    {:ok, fields} = Fields.from_answer(answer(changes))
    fields
  end

  describe "missing/2" do
    test "finds every recognised value of a receipt in its text" do
      assert Matching.missing(receipt_text(), fields()) == []
    end

    test "names the values the text does not have, in order" do
      assert Matching.missing(
               receipt_text(),
               fields(%{"price" => 145.76, "date" => "2026-10-02"})
             ) ==
               [:date, :price]
    end

    test "finds a charge the bank prints with a minus before or after" do
      fields = %Fields{amount: Decimal.new("879.28")}

      assert Matching.missing("Zu Ihren Lasten EUR -879,28", fields) == []
      assert Matching.missing("Betrag 879,28- EUR", fields) == []
    end

    test "finds numbers in English notation" do
      fields = %Fields{
        shares: Decimal.new("50"),
        amount: Decimal.new("2000"),
        taxes: Decimal.new("2.97")
      }

      text = "Buy Rocket Lab 50.00 pc. 40.00 EUR 2,000.00 EUR\nTaxes -2.55 EUR\nSoli -0.42 EUR"

      assert Matching.missing(text, fields) == []
    end

    test "finds no part of a longer number" do
      fields = %Fields{amount: Decimal.new("879.28"), price: Decimal.new("12")}

      assert Matching.missing("Betrag 1879,28 · Kurs 12,50", fields) == [:price, :amount]
    end

    test "finds a lone digit only as shares beside „Stück“" do
      shares = %Fields{shares: Decimal.new("5")}

      assert Matching.missing("Stück 5 Apple Inc.", shares) == []
      assert Matching.missing("5 Stück Apple Inc.", shares) == []
      assert Matching.missing("St. 5", shares) == []
      assert Matching.missing("Berechtigte Anzahl 5", shares) == []
      assert Matching.missing("Seite 5 von 6", shares) == [:shares]
      assert Matching.missing("Stück 5", %Fields{price: Decimal.new("5")}) == [:price]
    end

    test "needs no fees or taxes of zero to be printed" do
      fields = %Fields{fees: Decimal.new("0"), taxes: Decimal.new("0.00")}

      assert Matching.missing("Kauf", fields) == []
    end

    test "finds fees and taxes as the sum of the lines that list them" do
      text = """
      Kapitalertragsteuer 25,00 %   -23,50 EUR
      Solidaritätszuschlag 5,50 %    -1,29 EUR
      Ausmachender Betrag            69,21 EUR
      """

      assert Matching.missing(text, %Fields{taxes: Decimal.new("24.79")}) == []
      assert Matching.missing(text, %Fields{taxes: Decimal.new("90")}) == [:taxes]
      assert Matching.missing(text, %Fields{price: Decimal.new("24.79")}) == [:price]
    end

    test "finds ISIN, depot number and reference whatever their blanks" do
      fields = %Fields{isin: "IE00BK5BQT80", depot_number: "292782711", bank_reference: "SP 0001"}

      assert Matching.missing("IE00 BK5B QT80 · Depotnr. 2927827 11 · SP-0001", fields) ==
               [:bank_reference]
    end
  end

  test "regex/1 marks only the digit beside „Stück“ and is nil without values" do
    regex = Matching.regex(%Fields{shares: Decimal.new("5")})

    text = "Seite 1 · Stück 5"

    assert Regex.run(regex, text, return: :index) == [{byte_size(text) - 1, 1}]
    assert Matching.regex(%Fields{kind: :purchase}) == nil
  end

  test "german/2 writes a number in German notation" do
    assert Matching.german(Decimal.new("1125"), 2) == "1.125,00"
    assert Matching.german(Decimal.new("-0.5"), 4) == "0,5000"
  end
end
