defmodule AbakusWeb.Bookkeeping.InvoiceControllerTest do
  use AbakusWeb.ConnCase

  import Abakus.BookkeepingFixtures
  import Abakus.DomainFixtures

  alias Abakus.Bookkeeping
  alias Abakus.Users.Scope
  alias Abakus.UsersFixtures

  setup :register_and_log_in_user

  setup %{scope: scope} do
    {:ok, _ids} = Bookkeeping.put_business_accounts(scope, [account_fixture(kind: :tracking).id])
    sender_fixture(scope)
    :ok
  end

  @tag :typst
  test "downloads an invoice as PDF", %{conn: conn, scope: scope} do
    invoice = invoice_fixture(scope, customer_fixture(scope))

    conn = get(conn, ~p"/buchhaltung/invoices/#{invoice.id}/pdf")

    assert "%PDF-" <> _rest = response(conn, 200)
    assert response_content_type(conn, :pdf) =~ "application/pdf"

    assert get_resp_header(conn, "content-disposition") |> hd() =~
             ~s|filename="Rechnung 2027001.pdf"|
  end

  test "has no invoice of another user", %{conn: conn} do
    other = Scope.for_user(UsersFixtures.user_fixture())
    sender_fixture(other)
    theirs = invoice_fixture(other, customer_fixture(other))

    assert conn |> get(~p"/buchhaltung/invoices/#{theirs.id}/pdf") |> response(404)
    assert conn |> get(~p"/buchhaltung/invoices/x/pdf") |> response(404)
  end
end
