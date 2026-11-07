defmodule Abakus.Bookkeeping.InvoicePdfTest do
  use Abakus.DataCase

  import Abakus.BookkeepingFixtures

  alias Abakus.Bookkeeping.{EInvoice, InvoicePdf}
  alias Abakus.EInvoiceSchema
  alias Abakus.Users.Scope
  alias Abakus.UsersFixtures

  @moduletag :typst
  @moduletag :tmp_dir

  setup do
    scope = Scope.for_user(UsersFixtures.user_fixture())
    sender_fixture(scope)
    %{invoice: invoice_fixture(scope, customer_fixture(scope))}
  end

  defp write(pdf, dir) do
    path = Path.join(dir, "invoice.pdf")
    File.write!(path, pdf)
    path
  end

  defp metadata(path) do
    {xmp, 0} = System.cmd("pdfinfo", ["-meta", path])
    xmp
  end

  defp attachment(path, dir) do
    {list, 0} = System.cmd("pdfdetach", ["-list", path])
    out = Path.join(dir, EInvoice.filename())
    {_output, 0} = System.cmd("pdfdetach", ["-savefile", EInvoice.filename(), "-o", out, path])
    {list, File.read!(out)}
  end

  test "an invoice PDF is PDF/A-3 and carries valid EN 16931 XML", %{
    invoice: invoice,
    tmp_dir: dir
  } do
    assert {:ok, pdf} = InvoicePdf.render(invoice)
    path = write(pdf, dir)

    assert metadata(path) =~ ~r/pdfaid:part(>|=")3/
    assert metadata(path) =~ ~r/pdfaid:conformance(>|=")B/

    {list, xml} = attachment(path, dir)
    assert list =~ "factur-x.xml"
    assert xml == EInvoice.xml(invoice)
    assert EInvoiceSchema.errors(xml) == []
  end

  test "an invoice under reverse charge renders too", %{tmp_dir: dir} do
    scope = Scope.for_user(UsersFixtures.user_fixture())
    sender_fixture(scope)
    customer = customer_fixture(scope, %{"country" => "AT", "vat_id" => "ATU12345678"})
    invoice = invoice_fixture(scope, customer, %{"vat" => "reverse_charge"})

    assert {:ok, pdf} = InvoicePdf.render(invoice)
    {_list, xml} = pdf |> write(dir) |> attachment(dir)
    assert EInvoiceSchema.errors(xml) == []
  end
end
