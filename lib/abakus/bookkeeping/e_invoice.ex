defmodule Abakus.Bookkeeping.EInvoice do
  @moduledoc """
  An invoice as an e-invoice: the XML of EN 16931 in UN/CEFACT's Cross Industry Invoice syntax, profile EN 16931
  of ZUGFeRD and Factur-X, which the invoice's PDF carries as `factur-x.xml`.
  """

  import Abakus.Xml, only: [element: 2, element: 3]

  alias Abakus.Bookkeeping.{Invoice, Party, Position}
  alias Abakus.Money

  @namespaces [
    {"xmlns:rsm", "urn:un:unece:uncefact:data:standard:CrossIndustryInvoice:100"},
    {"xmlns:ram",
     "urn:un:unece:uncefact:data:standard:ReusableAggregateBusinessInformationEntity:100"},
    {"xmlns:udt", "urn:un:unece:uncefact:data:standard:UnqualifiedDataType:100"},
    {"xmlns:qdt", "urn:un:unece:uncefact:data:standard:QualifiedDataType:100"}
  ]

  @reverse_charge_note "Steuerschuldnerschaft des Leistungsempfängers"

  @doc "The name of the XML in the PDF."
  def filename, do: "factur-x.xml"

  @doc "The note an invoice under reverse charge carries."
  def reverse_charge_note, do: @reverse_charge_note

  def xml(%Invoice{} = invoice) do
    document =
      element("rsm:CrossIndustryInvoice", @namespaces, [
        element("rsm:ExchangedDocumentContext", [
          element("ram:GuidelineSpecifiedDocumentContextParameter", [
            element("ram:ID", "urn:cen.eu:en16931:2017")
          ])
        ]),
        element("rsm:ExchangedDocument", [
          element("ram:ID", invoice.number),
          element("ram:TypeCode", "380"),
          element("ram:IssueDateTime", [date(invoice.date)]),
          invoice.vat == :reverse_charge &&
            element("ram:IncludedNote", [element("ram:Content", @reverse_charge_note)])
        ]),
        element(
          "rsm:SupplyChainTradeTransaction",
          Enum.map(Enum.with_index(invoice.positions, 1), &line(&1, invoice)) ++
            [
              element("ram:ApplicableHeaderTradeAgreement", [
                element("ram:SellerTradeParty", party(invoice.sender, :seller)),
                element("ram:BuyerTradeParty", party(invoice.recipient, :buyer))
              ]),
              element("ram:ApplicableHeaderTradeDelivery", []),
              settlement(invoice)
            ]
        )
      ])

    IO.iodata_to_binary([~s(<?xml version="1.0" encoding="UTF-8"?>\n), document])
  end

  defp line({%Position{} = position, index}, invoice) do
    element("ram:IncludedSupplyChainTradeLineItem", [
      element("ram:AssociatedDocumentLineDocument", [
        element("ram:LineID", Integer.to_string(index))
      ]),
      element("ram:SpecifiedTradeProduct", [element("ram:Name", position.description)]),
      element("ram:SpecifiedLineTradeAgreement", [
        element("ram:NetPriceProductTradePrice", [
          element("ram:ChargeAmount", amount(position.unit_price))
        ])
      ]),
      element("ram:SpecifiedLineTradeDelivery", [
        element(
          "ram:BilledQuantity",
          [{"unitCode", position.unit}],
          Decimal.to_string(position.quantity, :normal)
        )
      ]),
      element("ram:SpecifiedLineTradeSettlement", [
        element("ram:ApplicableTradeTax", [
          element("ram:TypeCode", "VAT"),
          element("ram:CategoryCode", category(invoice.vat)),
          element("ram:RateApplicablePercent", rate(invoice.vat))
        ]),
        element("ram:SpecifiedTradeSettlementLineMonetarySummation", [
          element("ram:LineTotalAmount", amount(Position.net(position)))
        ])
      ])
    ])
  end

  defp party(%Party{} = party, role) do
    [
      element("ram:Name", party.name),
      element(
        "ram:PostalTradeAddress",
        [
          present?(party.postal_code) && element("ram:PostcodeCode", party.postal_code),
          present?(party.street) && element("ram:LineOne", party.street),
          present?(party.city) && element("ram:CityName", party.city),
          element("ram:CountryID", party.country)
        ]
      ),
      present?(party.vat_id) && tax_registration("VA", party.vat_id),
      role == :seller && present?(party.tax_number) && tax_registration("FC", party.tax_number)
    ]
  end

  defp tax_registration(scheme, id),
    do: element("ram:SpecifiedTaxRegistration", [element("ram:ID", [{"schemeID", scheme}], id)])

  defp settlement(invoice) do
    element("ram:ApplicableHeaderTradeSettlement", [
      element("ram:PaymentReference", invoice.number),
      element("ram:InvoiceCurrencyCode", "EUR"),
      element("ram:SpecifiedTradeSettlementPaymentMeans", [
        element("ram:TypeCode", "58"),
        element("ram:PayeePartyCreditorFinancialAccount", [
          element("ram:IBANID", invoice.sender.iban)
        ])
      ]),
      element("ram:ApplicableTradeTax", [
        element("ram:CalculatedAmount", amount(invoice.vat_amount)),
        element("ram:TypeCode", "VAT"),
        invoice.vat == :reverse_charge && element("ram:ExemptionReason", @reverse_charge_note),
        element("ram:BasisAmount", amount(invoice.net)),
        element("ram:CategoryCode", category(invoice.vat)),
        invoice.vat == :reverse_charge && element("ram:ExemptionReasonCode", "VATEX-EU-AE"),
        element("ram:RateApplicablePercent", rate(invoice.vat))
      ]),
      element("ram:BillingSpecifiedPeriod", [
        element("ram:StartDateTime", [date(invoice.service_from)]),
        element("ram:EndDateTime", [date(invoice.service_to)])
      ]),
      element("ram:SpecifiedTradePaymentTerms", [
        element("ram:DueDateDateTime", [date(invoice.due_date)])
      ]),
      element("ram:SpecifiedTradeSettlementHeaderMonetarySummation", [
        element("ram:LineTotalAmount", amount(invoice.net)),
        element("ram:TaxBasisTotalAmount", amount(invoice.net)),
        element("ram:TaxTotalAmount", [{"currencyID", "EUR"}], amount(invoice.vat_amount)),
        element("ram:GrandTotalAmount", amount(invoice.total)),
        element("ram:DuePayableAmount", amount(invoice.total))
      ])
    ])
  end

  defp category(:reverse_charge), do: "AE"
  defp category(_rate), do: "S"

  defp rate(treatment), do: Integer.to_string(Invoice.rate(treatment))

  defp date(%Date{} = date),
    do: element("udt:DateTimeString", [{"format", "102"}], Calendar.strftime(date, "%Y%m%d"))

  defp amount(cents), do: Money.format_minor(cents, 2, separator: ".")

  defp present?(value), do: value not in [nil, ""]
end
