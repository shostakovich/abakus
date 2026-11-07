defmodule Abakus.Bookkeeping.Lexoffice.RecordsTest do
  use ExUnit.Case, async: true

  alias Abakus.Bookkeeping.Lexoffice.Records

  defp invoice(attrs) do
    Map.merge(
      %{
        "id" => "inv",
        "voucherStatus" => "paid",
        "voucherNumber" => "2026007",
        "voucherDate" => "2026-01-31T00:00:00.000+01:00",
        "taxConditions" => %{"taxType" => "net"},
        "totalPrice" => %{
          "totalNetAmount" => 100,
          "totalTaxAmount" => 19,
          "totalGrossAmount" => 119
        },
        "lineItems" => [item(19)],
        "address" => %{"name" => "Kunde"}
      },
      attrs
    )
  end

  defp item(rate, attrs \\ %{}),
    do:
      Map.merge(
        %{
          "type" => "custom",
          "name" => "Arbeit",
          "quantity" => 1,
          "unitName" => "Stunde",
          "unitPrice" => %{"netAmount" => 100, "taxRatePercentage" => rate}
        },
        attrs
      )

  test "a counter is what follows the year, 0 for another form of number" do
    assert Records.counter("2026125") == 125
    assert Records.counter("2019032") == 32
    assert Records.counter("RE-2026-1") == 0
    assert Records.counter(nil) == 0
  end

  test "amounts in euros become cents without float errors" do
    assert Records.cents(245.18) == 24_518
    assert Records.cents(0.29) == 29
    assert Records.cents(4820.39) == 482_039
    assert Records.cents(12) == 1200
    assert Records.cents("12") == nil
  end

  test "a customer is named after its company or its person" do
    assert Records.customer(%{
             "id" => "c",
             "person" => %{"firstName" => "Erika", "lastName" => "Beispiel"}
           }) ==
             %{
               lexoffice_id: "c",
               name: "Erika Beispiel",
               street: nil,
               postal_code: nil,
               city: nil,
               country: "DE",
               vat_id: nil
             }

    assert Records.customer?(%{"roles" => %{"customer" => %{}, "vendor" => %{}}})
    refute Records.customer?(%{"roles" => %{"vendor" => %{}}})
  end

  test "the VAT follows the tax type and the one rate of the positions" do
    assert {:ok, %{vat: :rate_19}} = Records.invoice(invoice(%{}))
    assert {:ok, %{vat: :rate_7}} = Records.invoice(invoice(%{"lineItems" => [item(7.0)]}))

    assert {:ok, %{vat: :rate_16}} =
             Records.invoice(
               invoice(%{"taxConditions" => %{"taxType" => "gross"}, "lineItems" => [item(16)]})
             )

    assert {:ok, %{vat: :reverse_charge}} =
             Records.invoice(
               invoice(%{
                 "taxConditions" => %{"taxType" => "intraCommunitySupply"},
                 "lineItems" => [item(0)]
               })
             )

    assert Records.invoice(invoice(%{"lineItems" => [item(19), item(7)]})) ==
             {:error, "mit mehreren Steuersätzen"}

    assert Records.invoice(invoice(%{"lineItems" => [item(0)]})) ==
             {:error, "mit 0 % Umsatzsteuer"}

    assert Records.invoice(
             invoice(%{"taxConditions" => %{"taxType" => "thirdPartyCountryService"}})
           ) ==
             {:error, "mit der Steuerart „thirdPartyCountryService“"}
  end

  test "units are read from their names, an unknown one as a piece, and text lines are left out" do
    items = [
      item(19, %{"unitName" => "Tage"}),
      item(19, %{"unitName" => "pauschal"}),
      item(19, %{"unitName" => "Seiten", "quantity" => 2.5}),
      %{"type" => "text", "name" => "Hinweis"}
    ]

    assert {:ok, %{positions: positions}} = Records.invoice(invoice(%{"lineItems" => items}))
    assert Enum.map(positions, & &1.unit) == ["DAY", "LS", "C62"]
    assert Enum.at(positions, 2).quantity == Decimal.new("2.5")
  end

  test "without a service period the period is the invoice's day" do
    assert {:ok,
            %{service_from: ~D[2026-01-31], service_to: ~D[2026-01-31], due_date: ~D[2026-01-31]}} =
             Records.invoice(invoice(%{"shippingConditions" => %{"shippingType" => "none"}}))
  end

  test "an invoice is paid on the day Lexoffice saw it paid in full, else its last payment, else its date" do
    json = invoice(%{})

    assert Records.status(json, %{"paidDate" => "2026-02-03T00:00:00.000+01:00"}) ==
             %{paid_on: ~D[2026-02-03], voided: false}

    payments = %{
      "paymentItems" => [
        %{"postingDate" => "2026-02-10T00:00:00.000+01:00"},
        %{"postingDate" => "2026-02-05T00:00:00.000+01:00"}
      ]
    }

    assert Records.status(json, payments) == %{paid_on: ~D[2026-02-10], voided: false}
    assert Records.status(json, nil) == %{paid_on: ~D[2026-01-31], voided: false}

    assert Records.status(%{json | "voucherStatus" => "open"}, nil) == %{
             paid_on: nil,
             voided: false
           }

    assert Records.status(%{json | "voucherStatus" => "voided"}, nil) == %{
             paid_on: nil,
             voided: true
           }
  end
end
