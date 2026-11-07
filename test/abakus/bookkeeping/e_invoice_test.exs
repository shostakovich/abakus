defmodule Abakus.Bookkeeping.EInvoiceTest do
  use Abakus.DataCase

  import Abakus.BookkeepingFixtures

  alias Abakus.Bookkeeping.EInvoice
  alias Abakus.EInvoiceSchema
  alias Abakus.Users.Scope
  alias Abakus.UsersFixtures

  setup do
    scope = Scope.for_user(UsersFixtures.user_fixture())
    sender_fixture(scope)
    %{scope: scope}
  end

  defp text(xml, path), do: EInvoiceSchema.texts(xml, path)

  test "an invoice is valid EN 16931 XML", %{scope: scope} do
    xml = EInvoice.xml(invoice_fixture(scope, customer_fixture(scope)))

    assert EInvoiceSchema.errors(xml) == []

    assert text(xml, "//ram:GuidelineSpecifiedDocumentContextParameter/ram:ID") == [
             "urn:cen.eu:en16931:2017"
           ]

    assert text(xml, "//rsm:ExchangedDocument/ram:ID") == ["2027001"]
    assert text(xml, "//ram:BuyerTradeParty/ram:Name") == ["Muster & Söhne GmbH"]
    assert text(xml, "//ram:BilledQuantity") == ["7.5", "1"]
    assert text(xml, "//ram:LineTotalAmount") == ["712.50", "120.00", "832.50"]

    assert text(
             xml,
             "//ram:ApplicableHeaderTradeSettlement/ram:ApplicableTradeTax/ram:CalculatedAmount"
           ) == ["158.18"]

    assert text(xml, "//ram:DuePayableAmount") == ["990.68"]

    assert text(xml, "//ram:BillingSpecifiedPeriod/*/udt:DateTimeString") == [
             "20261201",
             "20261231"
           ]

    assert text(xml, "//ram:SellerTradeParty/ram:SpecifiedTaxRegistration/ram:ID") == [
             "DE123456789",
             "30/123/45678"
           ]
  end

  test "leaves out the address lines a party lacks", %{scope: scope} do
    invoice = invoice_fixture(scope, customer_fixture(scope))
    recipient = %{invoice.recipient | street: nil, postal_code: nil, city: nil}
    xml = EInvoice.xml(%{invoice | recipient: recipient})

    assert text(xml, "//ram:BuyerTradeParty/ram:PostalTradeAddress/*") == ["DE"]
  end

  test "an invoice under reverse charge is valid EN 16931 XML", %{scope: scope} do
    customer = customer_fixture(scope, %{"country" => "AT", "vat_id" => "ATU12345678"})
    xml = EInvoice.xml(invoice_fixture(scope, customer, %{"vat" => "reverse_charge"}))

    assert EInvoiceSchema.errors(xml) == []

    assert text(
             xml,
             "//ram:ApplicableHeaderTradeSettlement/ram:ApplicableTradeTax/ram:CategoryCode"
           ) == ["AE"]

    assert text(xml, "//ram:ExemptionReasonCode") == ["VATEX-EU-AE"]

    assert text(xml, "//ram:BuyerTradeParty/ram:SpecifiedTaxRegistration/ram:ID") == [
             "ATU12345678"
           ]
  end
end
