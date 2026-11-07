defmodule Abakus.Bookkeeping.InvoicesTest do
  use Abakus.DataCase

  import Abakus.BookkeepingFixtures

  alias Abakus.Bookkeeping.{Customer, Invoice, Invoices, Settings}
  alias Abakus.Users.Scope
  alias Abakus.UsersFixtures

  setup do
    scope = Scope.for_user(UsersFixtures.user_fixture())
    sender_fixture(scope)
    %{scope: scope, customer: customer_fixture(scope)}
  end

  defp imported!(invoice, number, counter) do
    invoice |> Ecto.Changeset.change(number: number, counter: counter) |> Repo.update!()
  end

  describe "invoice numbers" do
    test "continue the Lexoffice sequence", %{scope: scope, customer: customer} do
      scope |> invoice_fixture(customer, %{"date" => "2026-12-20"}) |> imported!("2026125", 125)

      invoice = invoice_fixture(scope, customer, %{"date" => "2027-01-15"})

      assert invoice.number == "2027126"
      assert invoice.counter == 126
    end

    test "start at the first counter of the invoice's year", %{scope: scope, customer: customer} do
      assert invoice_fixture(scope, customer, %{"date" => "2027-03-02"}).number == "2027001"
      assert invoice_fixture(scope, customer, %{"date" => "2027-03-03"}).number == "2027002"
    end

    test "are counted per user", %{scope: scope, customer: customer} do
      invoice_fixture(scope, customer)
      other = Scope.for_user(UsersFixtures.user_fixture())
      sender_fixture(other)

      assert invoice_fixture(other, customer_fixture(other)).number == "2027001"
    end
  end

  describe "writing an invoice" do
    test "adds up the positions and fixes the due date", %{scope: scope, customer: customer} do
      invoice = invoice_fixture(scope, customer)

      assert [%{quantity: quantity, unit_price: 9500}, %{unit_price: 12_000}] = invoice.positions
      assert Decimal.equal?(quantity, Decimal.new("7.5"))
      assert {invoice.net, invoice.vat_amount, invoice.total} == {83_250, 15_818, 99_068}
      assert invoice.due_date == ~D[2027-01-29]
    end

    test "keeps the sender and the customer as they were", %{scope: scope, customer: customer} do
      invoice = invoice_fixture(scope, customer)
      {:ok, _customer} = Invoices.update_customer(scope, customer, %{"name" => "Neu GmbH"})
      sender_fixture(scope, %{"name" => "Anders"})

      invoice = Invoices.get_invoice(scope, invoice.id)
      assert invoice.recipient.name == "Muster & Söhne GmbH"
      assert invoice.sender.name == "Robert Beispiel"
      assert invoice.sender.iban == "DE89370400440532013000"
      assert invoice.sender.country == "DE"
    end

    test "needs the sender in the settings", %{customer: customer} do
      scope = Scope.for_user(UsersFixtures.user_fixture())
      customer = customer_fixture(scope, %{"name" => customer.name})

      assert Invoices.write_invoice(scope, invoice_attrs(customer)) == {:error, :no_sender}
    end

    test "needs a position and a service period in order", %{scope: scope, customer: customer} do
      attrs = invoice_attrs(customer, %{"positions" => %{}, "service_to" => "2026-11-30"})

      assert {:error, changeset} = Invoices.write_invoice(scope, attrs)
      assert %{positions: [_], service_to: ["liegt vor dem Beginn"]} = errors_on(changeset)
    end

    test "takes only the user's own customers", %{scope: scope} do
      other = Scope.for_user(UsersFixtures.user_fixture())
      theirs = customer_fixture(other)

      assert {:error, changeset} = Invoices.write_invoice(scope, invoice_attrs(theirs))
      assert %{customer_id: ["nicht gefunden"]} = errors_on(changeset)
    end

    test "under reverse charge has no VAT, for a business in another EU country", %{scope: scope} do
      austrian =
        customer_fixture(scope, %{"country" => "AT", "vat_id" => "ATU 12345678", "city" => "Wien"})

      invoice = invoice_fixture(scope, austrian, %{"vat" => "reverse_charge"})

      assert {invoice.net, invoice.vat_amount, invoice.total} == {83_250, 0, 83_250}
      assert invoice.recipient.vat_id == "ATU12345678"
    end

    test "refuses a customer without a full address", %{scope: scope} do
      {:ok, imported} =
        %Customer{user_id: scope.user.id}
        |> Customer.import_changeset(%{name: "Ohne Anschrift", country: "DE", lexoffice_id: "c1"})
        |> Repo.insert()

      assert {:error, changeset} = Invoices.write_invoice(scope, invoice_attrs(imported))

      assert %{customer_id: ["Der Kunde braucht eine vollständige Anschrift."]} =
               errors_on(changeset)

      assert Invoices.list_invoices(scope) == []
    end

    test "refuses reverse charge for a customer in Germany", %{scope: scope, customer: customer} do
      attrs = invoice_attrs(customer, %{"vat" => "reverse_charge"})

      assert {:error, changeset} = Invoices.write_invoice(scope, attrs)
      assert %{vat: ["nur für Kunden im EU-Ausland mit USt-IdNr."]} = errors_on(changeset)
    end
  end

  test "lists the user's invoices, the latest first", %{scope: scope, customer: customer} do
    first = invoice_fixture(scope, customer)
    second = invoice_fixture(scope, customer)

    assert Enum.map(Invoices.list_invoices(scope), & &1.id) == [second.id, first.id]
    assert Invoices.list_invoices(Scope.for_user(UsersFixtures.user_fixture())) == []
  end

  test "a new invoice is for the month before", %{} do
    assert %Invoice{service_from: ~D[2026-12-01], service_to: ~D[2026-12-31], vat: :rate_19} =
             Invoices.new_invoice(~D[2027-01-15])
  end

  describe "settings" do
    test "check the IBAN", %{scope: scope} do
      assert {:error, changeset} =
               Settings.save_settings(scope, %{"iban" => "DE89 3704 0044 0532 0130 01"})

      assert %{iban: ["ist keine gültige IBAN"]} = errors_on(changeset)
    end

    test "may lose the IBAN and the VAT id again", %{scope: scope} do
      assert {:ok, settings} = Settings.save_settings(scope, %{"iban" => "", "vat_id" => ""})
      assert {settings.iban, settings.vat_id} == {nil, nil}
    end

    test "are complete with name, address, IBAN and a tax number or VAT id" do
      complete = %Settings{
        name: "A",
        street: "B",
        postal_code: "1",
        city: "C",
        iban: "DE89370400440532013000",
        tax_number: "1"
      }

      assert Settings.complete?(complete)
      assert Settings.complete?(%{complete | tax_number: nil, vat_id: "DE1"})
      refute Settings.complete?(%{complete | tax_number: nil})
      refute Settings.complete?(%{complete | iban: ""})
    end
  end

  describe "customers" do
    test "are the user's, by name", %{scope: scope, customer: customer} do
      other = Scope.for_user(UsersFixtures.user_fixture())
      customer_fixture(other)
      aachen = customer_fixture(scope, %{"name" => "aachener Firma"})

      assert Enum.map(Invoices.list_customers(scope), & &1.id) == [aachen.id, customer.id]
      assert Invoices.get_customer(other, customer.id) == nil
    end

    test "may lose the VAT id, not the name", %{scope: scope} do
      customer = customer_fixture(scope, %{"vat_id" => "ATU12345678", "country" => "AT"})

      assert {:ok, %{vat_id: nil}} = Invoices.update_customer(scope, customer, %{"vat_id" => ""})
      assert {:error, changeset} = Invoices.update_customer(scope, customer, %{"name" => ""})
      assert %{name: [_]} = errors_on(changeset)
    end

    test "need a name and an address", %{scope: scope} do
      assert {:error, changeset} =
               Invoices.create_customer(scope, %{"name" => " ", "country" => "XX"})

      assert %{name: [_], street: [_], postal_code: [_], city: [_], country: [_]} =
               errors_on(changeset)
    end
  end
end
