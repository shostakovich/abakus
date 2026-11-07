defmodule Abakus.Bookkeeping.LexofficeImportTest do
  use Abakus.DataCase

  import Abakus.BookkeepingFixtures
  import Abakus.DomainFixtures

  alias Abakus.{FakePaperless, Paperless, Repo}

  alias Abakus.Bookkeeping.{
    Customer,
    FakeLexoffice,
    Invoice,
    InvoicePayments,
    Invoices,
    LexofficeImport
  }

  @url "http://paperless.test"
  @key "lexoffice-key"

  setup do
    scope = budget_scope()
    {:ok, _connection} = Paperless.update_connection(scope, %{"url" => @url, "token" => "t"})
    FakePaperless.serve(%{@url => %{token: "t", documents: []}})
    FakeLexoffice.serve(@key)
    %{scope: scope}
  end

  defp run(scope, key \\ @key), do: LexofficeImport.run(scope, fn -> key end)

  defp invoice(scope, number),
    do: Enum.find(Invoices.list_invoices(scope), &(&1.number == number))

  defp snapshot(scope) do
    %{
      customers: Enum.map(Invoices.list_customers(scope), &Map.drop(&1, [:__meta__])),
      invoices: Enum.map(Invoices.list_invoices(scope), &Map.drop(&1, [:__meta__])),
      documents: FakePaperless.documents(@url)
    }
  end

  test "the import against recorded responses creates customers and invoices, and a second run changes nothing",
       %{scope: scope} do
    assert {:ok, result} = run(scope)
    assert result.customers == 3
    assert result.invoices == 4
    assert result.skipped == [{"2025110", "Rechnung mit mehreren Steuersätzen"}]

    assert Enum.map(Invoices.list_customers(scope), & &1.name) ==
             ["Erika Beispiel", "Esempio Digitale S.r.l.", "Jonas Käufer", "Muster & Söhne GmbH"]

    assert Enum.map(Invoices.list_invoices(scope), & &1.number) ==
             ["2026125", "2026124", "2024102", "2020041"]

    before = snapshot(scope)
    requests = length(FakeLexoffice.requests())

    assert run(scope) == {:ok, %{customers: 0, invoices: 0, skipped: result.skipped}}
    assert snapshot(scope) == before

    assert Enum.drop(FakeLexoffice.requests(), requests) ==
             [
               "contacts",
               "voucherlist",
               "voucherlist-1",
               "invoices/bbbbbbbb-0000-4000-8000-000000000005"
             ]
  end

  test "an imported invoice keeps Lexoffice's numbers, period and VAT and its original PDF in Paperless",
       %{scope: scope} do
    {:ok, _result} = run(scope)

    invoice = invoice(scope, "2020041")
    assert invoice.counter == 41
    assert invoice.date == ~D[2020-09-01]
    assert invoice.due_date == ~D[2020-09-15]
    assert {invoice.service_from, invoice.service_to} == {~D[2020-08-01], ~D[2020-08-31]}
    assert invoice.vat == :rate_16
    assert {invoice.net, invoice.vat_amount, invoice.total} == {95_000, 15_200, 110_200}
    assert invoice.paid_on == ~D[2020-09-10]
    refute invoice.voided

    assert [%{description: "Softwareentwicklung\nAugust 2020", unit: "HUR", unit_price: 9500}] =
             invoice.positions

    assert invoice.recipient.name == "Muster & Söhne GmbH"
    assert invoice.customer_id == Repo.get_by!(Customer, name: "Muster & Söhne GmbH").id

    document = Enum.find(FakePaperless.documents(@url), &(&1.id == invoice.paperless_id))
    assert document.title == "Rechnung 2020041"
    assert document.pdf =~ "Lexoffice Rechnung 2020041"
    assert Invoice.imported?(invoice)
  end

  test "an invoice without a file id has its PDF rendered, and one to a mere address gets a customer of it",
       %{scope: scope} do
    {:ok, _result} = run(scope)

    invoice = invoice(scope, "2026124")
    assert {invoice.service_from, invoice.service_to} == {~D[2026-02-27], ~D[2026-02-27]}
    assert {invoice.net, invoice.vat_amount, invoice.total} == {42_017, 7983, 50_000}
    assert [%{unit: "C62", unit_price: 42_017}] = invoice.positions

    customer = Repo.get!(Customer, invoice.customer_id)

    assert {customer.name, customer.city, customer.lexoffice_id} ==
             {"Jonas Käufer", "Hamburg", nil}

    assert "invoices/bbbbbbbb-0000-4000-8000-000000000003/document" in FakeLexoffice.requests()
  end

  test "a voided invoice stays voided and an open one open, with reverse charge to a customer abroad",
       %{scope: scope} do
    {:ok, _result} = run(scope)

    voided = invoice(scope, "2024102")
    assert voided.voided
    assert voided.paid_on == nil

    open = invoice(scope, "2026125")
    assert open.vat == :reverse_charge
    assert open.paid_on == nil
    assert open.recipient.vat_id == "IT01234567897"
    assert [%{unit: "MON"}, %{unit: "HUR"}] = open.positions
    refute Invoice.settled?(open)
    assert Invoice.settled?(voided)
    refute "payments/bbbbbbbb-0000-4000-8000-000000000004" in FakeLexoffice.requests()
  end

  test "invoices continue the Lexoffice sequence", %{scope: scope} do
    {:ok, _result} = run(scope)
    sender_fixture(scope)
    customer = Repo.get_by!(Customer, name: "Muster & Söhne GmbH")

    assert invoice_fixture(scope, customer, %{"date" => "2027-01-15"}).number == "2027126"
  end

  test "an invoice paid or voided in Lexoffice takes no payment here", %{scope: scope} do
    business = account_fixture(kind: :tracking)
    {:ok, _ids} = Abakus.Bookkeeping.put_business_accounts(scope, [business.id])
    {:ok, _result} = run(scope)

    paid = invoice(scope, "2026124")
    transaction_fixture(%{account_id: business.id, date: ~D[2026-03-05], amount: 50_000})

    assert InvoicePayments.proposals(scope, [paid, invoice(scope, "2024102")]) == %{}
    assert {:error, :paid} = InvoicePayments.confirm(scope, paid, Ecto.UUID.generate())
  end

  test "a customer of the same name made before is linked to the contact and keeps its address",
       %{scope: scope} do
    customer = customer_fixture(scope, %{"name" => "muster & söhne gmbh", "city" => "Augsburg"})
    {:ok, _result} = run(scope)

    assert invoice(scope, "2020041").customer_id == customer.id

    assert Repo.all(
             from c in Customer, where: c.lexoffice_id == "aaaaaaaa-0000-4000-8000-000000000001"
           ) ==
             [Repo.get!(Customer, customer.id)]

    assert Repo.get!(Customer, customer.id).city == "Augsburg"
  end

  test "a key Lexoffice refuses stops the import before anything comes over", %{scope: scope} do
    assert run(scope, "wrong") == {:error, :unauthorized}
    assert Invoices.list_customers(scope) == []
  end

  test "without Paperless the import does not start", %{scope: scope} do
    {:ok, _connection} = Paperless.disconnect(scope)

    assert run(scope) == {:error, :not_connected}
    assert FakeLexoffice.requests() == []
  end

  test "an error of Lexoffice stops the import, and a second run goes on from there", %{
    scope: scope
  } do
    stop_supervised!(FakeLexoffice)

    FakeLexoffice.serve(@key, %{
      "invoices/bbbbbbbb-0000-4000-8000-000000000003" => {:error, :unreachable}
    })

    assert run(scope) == {:error, :unreachable}
    assert Enum.map(Invoices.list_invoices(scope), & &1.number) == ["2024102", "2020041"]

    stop_supervised!(FakeLexoffice)
    FakeLexoffice.serve(@key)

    assert {:ok, %{invoices: 2}} = run(scope)
    assert length(Invoices.list_invoices(scope)) == 4
  end

  test "reports each step to the progress callback", %{scope: scope} do
    test = self()
    {:ok, _result} = LexofficeImport.run(scope, fn -> @key end, &send(test, {:progress, &1}))

    assert_received {:progress, {:customers, 3}}
    assert_received {:progress, {:invoices, 0, 5}}
    assert_received {:progress, {:invoices, 5, 5}}
  end
end
