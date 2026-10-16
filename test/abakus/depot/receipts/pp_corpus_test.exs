defmodule Abakus.Depot.Receipts.PPCorpusTest do
  use ExUnit.Case, async: true

  alias Abakus.Depot.Receipts.PPCorpus

  # Made-up tests in the style of Portfolio Performance's PDF importer tests.
  @java """
  public class MusterbankPDFExtractorTest
  {
      @Test
      public void testKauf01()
      {
          var results = extractor.extract(PDFInputFile.loadTestCase(getClass(), "Kauf01.txt"), errors);
          assertThat(results, hasItem(security(hasIsin("IE00BK5BQT80"), hasName("Musterfonds"))));
          assertThat(results, hasItem(purchase(hasDate("2026-03-16T09:04:12"), hasShares(15.00),
                          hasAmount("EUR", 1691.55), hasGrossValue("EUR", 1685.10),
                          hasTaxes("EUR", 0.00), hasFees("EUR", 6.45))));
      }

      @Test
      public void testKauf01WithSecurityInEUR()
      {
          var results = extractor.extract(PDFInputFile.loadTestCase(getClass(), "Kauf01.txt"), errors);
          assertThat(results, hasItem(purchase(hasDate("2026-03-16T09:04:12"), hasShares(15.00),
                          hasAmount("EUR", 1691.55), hasTaxes("EUR", 0.00), hasFees("EUR", 6.45))));
      }

      @Test
      public void testDividende01()
      {
          var results = extractor.extract(PDFInputFile.loadTestCase(getClass(), "Dividende01.txt"), errors);
          assertThat(results, hasItem(security(hasIsin("US0378331005"))));
          assertThat(results, hasItem(dividend(hasDate("2026-05-20T00:00"), hasShares(40),
                          hasAmount("EUR", 0.07), hasForexGrossValue("USD", 0.08),
                          hasTaxes("EUR", 0.01), hasFees("EUR", 0.00))));
      }

      @Test
      public void testKontoauszug01()
      {
          var results = extractor.extract(PDFInputFile.loadTestCase(getClass(), "Kontoauszug01.txt"), errors);
          assertThat(results, hasItem(deposit(hasDate("2026-01-02"), hasAmount("EUR", 100.00))));
          assertThat(results, hasItem(removal(hasDate("2026-01-03"), hasAmount("EUR", 50.00))));
      }
  }
  """

  test "derives a case per text with a single purchase, sale or dividend in the home currency" do
    assert {[{"Kauf01.txt", expected}], 2} = PPCorpus.cases(@java)

    assert expected == %{
             kind: "purchase",
             date: "2026-03-16",
             isin: "IE00BK5BQT80",
             security_name: nil,
             shares: "15.00",
             price: nil,
             fees: "6.45",
             taxes: "0.00",
             amount: "1691.55",
             depot_number: nil,
             bank_reference: nil,
             unscored: ~w(price depot_number bank_reference)
           }
  end

  test "drops the lines Portfolio Performance puts on top of a text" do
    text = "PDFBox Version: 1.8.17\n-----------------------------------------\nMusterbank\nKauf\n"
    assert PPCorpus.text(text) == "Musterbank\nKauf\n"
    assert PPCorpus.text("Musterbank\n-----\nKauf\n") == "Musterbank\n-----\nKauf\n"
  end
end
