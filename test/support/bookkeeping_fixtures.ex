defmodule Abakus.BookkeepingFixtures do
  @moduledoc "The sender, ELSTER, customers, invoices and fixed assets of the Buchhaltung for tests."

  alias Abakus.Bookkeeping.{FakeLexoffice, Filings, FixedAssets, Invoices, LexofficeImport}
  alias Abakus.{FakePaperless, Paperless}
  alias Abakus.Users.Scope

  @paperless "http://paperless.test"

  @doc "The customers and invoices of the recorded Lexoffice responses, imported with the PDFs in a Paperless."
  def lexoffice_fixture(%Scope{} = scope) do
    {:ok, _connection} =
      Paperless.update_connection(scope, %{"url" => @paperless, "token" => "t"})

    FakePaperless.serve(%{@paperless => %{token: "t", documents: []}})
    FakeLexoffice.serve("lexoffice-key")
    {:ok, _result} = LexofficeImport.run(scope, fn -> "lexoffice-key" end)
    Map.new(Invoices.list_invoices(scope), &{&1.number, &1})
  end

  def sender_attrs(attrs \\ %{}) do
    Enum.into(attrs, %{
      "name" => "Robert Beispiel",
      "street" => "Lindenallee 4",
      "postal_code" => "10115",
      "city" => "Berlin",
      "vat_id" => "DE123456789",
      "tax_number" => "30/123/45678",
      "iban" => "DE89 3704 0044 0532 0130 00",
      "payment_days" => "14"
    })
  end

  def sender_fixture(%Scope{} = scope, attrs \\ %{}) do
    {:ok, settings} = Invoices.save_settings(scope, sender_attrs(attrs))
    settings
  end

  @doc "The sender with the state of their tax office and an ELSTER certificate, all that sending needs."
  def elster_fixture(%Scope{} = scope) do
    sender_fixture(scope, %{"tax_state" => "BE", "business_activity" => "Softwareentwicklung"})
    {:ok, settings} = Filings.put_certificate(scope, {"PKCS12 certificate", "Robert.pfx"})
    settings
  end

  def customer_fixture(%Scope{} = scope, attrs \\ %{}) do
    {:ok, customer} =
      Invoices.create_customer(
        scope,
        Enum.into(attrs, %{
          "name" => "Muster & Söhne GmbH",
          "street" => "Hauptstraße 1",
          "postal_code" => "80331",
          "city" => "München",
          "country" => "DE"
        })
      )

    customer
  end

  def invoice_attrs(customer, attrs \\ %{}) do
    Enum.into(attrs, %{
      "customer_id" => customer.id,
      "date" => "2027-01-15",
      "service_from" => "2026-12-01",
      "service_to" => "2026-12-31",
      "vat" => "19",
      "positions" => %{
        "0" => %{
          "description" => "Softwareentwicklung",
          "quantity" => "7,5",
          "unit" => "HUR",
          "unit_price" => "95,00"
        },
        "1" => %{
          "description" => "Reisekosten",
          "quantity" => "1",
          "unit" => "LS",
          "unit_price" => "120"
        }
      }
    })
  end

  def invoice_fixture(%Scope{} = scope, customer, attrs \\ %{}) do
    {:ok, invoice} = Invoices.write_invoice(scope, invoice_attrs(customer, attrs))
    invoice
  end

  def fixed_asset_fixture(%Scope{} = scope, attrs \\ %{}) do
    {:ok, asset} =
      FixedAssets.create(
        scope,
        Enum.into(attrs, %{
          "name" => "Notebook",
          "purchased_on" => "2027-04-10",
          "net" => "2.400,00",
          "useful_life" => "3"
        })
      )

    asset
  end

  def disposal_fixture(%Scope{} = scope, asset, attrs \\ %{}) do
    {:ok, asset} =
      FixedAssets.record_disposal(
        scope,
        asset,
        Enum.into(attrs, %{
          "kind" => "sale",
          "date" => "2027-01-20",
          "amount" => "238",
          "vat" => "19"
        })
      )

    asset
  end
end
