defmodule Abakus.BookkeepingFixtures do
  @moduledoc "The sender, customers and invoices of the Buchhaltung for tests."

  alias Abakus.Bookkeeping.Invoices
  alias Abakus.Users.Scope

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
end
