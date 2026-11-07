defmodule AbakusWeb.Bookkeeping.InvoicesLiveTest do
  use AbakusWeb.ConnCase

  import Phoenix.LiveViewTest
  import Abakus.BookkeepingFixtures
  import Abakus.DomainFixtures
  import Setzkasten.Test.Confirm

  alias Abakus.Bookkeeping
  alias Abakus.Bookkeeping.Invoices

  setup :register_and_log_in_user

  setup %{scope: scope} do
    {:ok, _ids} = Bookkeeping.put_business_accounts(scope, [account_fixture(kind: :tracking).id])
    fix_today(~D[2027-01-15])
    :ok
  end

  defp position(description, quantity, price),
    do: %{
      "description" => description,
      "quantity" => quantity,
      "unit" => "HUR",
      "unit_price" => price
    }

  test "the owner writes an invoice that continues the Lexoffice sequence", %{
    conn: conn,
    scope: scope
  } do
    sender_fixture(scope)
    customer = customer_fixture(scope)

    scope
    |> invoice_fixture(customer, %{"date" => "2026-12-20"})
    |> Ecto.Changeset.change(number: "2026125", counter: 125)
    |> Abakus.Repo.update!()

    {:ok, view, _html} = live(conn, ~p"/buchhaltung/invoices/new")
    assert has_element?(view, "#side-bookkeeping-invoices-sidebar[aria-current=page]")
    assert has_element?(view, "#invoice_service_from[value='2026-12-01']")

    params = %{
      "customer_id" => customer.id,
      "positions" => %{"0" => position("Beratung", "8", "95,00")}
    }

    assert view |> form("#invoice-form", invoice: params) |> render_change() =~ "904,40"

    {:ok, list, html} =
      view
      |> confirm_click("#invoice-write", "Rechnung schreiben?", with: %{invoice: params})
      |> follow_redirect(conn, ~p"/buchhaltung/invoices")

    assert html =~ "Rechnung 2027126 geschrieben."

    [invoice, _imported] = Invoices.list_invoices(scope)
    assert invoice.number == "2027126"
    assert invoice.total == 90_440
    assert has_element?(list, "#invoice-#{invoice.id}", "2027126 · Muster & Söhne GmbH")

    assert has_element?(
             list,
             ~s|#invoice-#{invoice.id}-download[href="/buchhaltung/invoices/#{invoice.id}/pdf"]|
           )
  end

  test "adds and removes positions", %{conn: conn, scope: scope} do
    sender_fixture(scope)
    customer_fixture(scope)
    {:ok, view, _html} = live(conn, ~p"/buchhaltung/invoices/new")

    assert has_element?(
             view,
             ~s|#invoice-position-add[name="invoice[positions_sort][]"][value=new]|
           )

    view
    |> form("#invoice-form")
    |> render_change(%{"invoice" => %{"positions_sort" => ["0", "new"]}})

    assert has_element?(view, "#invoice-position-1")

    view
    |> form("#invoice-form",
      invoice: %{
        "positions" => %{"0" => position("A", "1", "10"), "1" => position("B", "2", "5")}
      }
    )
    |> render_change()

    assert has_element?(view, "#invoice-total", "23,80")

    assert has_element?(
             view,
             ~s|#invoice-position-0-remove[name="invoice[positions_drop][]"][value="0"]|
           )

    view |> form("#invoice-form") |> render_change(%{"invoice" => %{"positions_drop" => ["0"]}})
    refute has_element?(view, "#invoice-position-1")
    assert has_element?(view, "#invoice-total", "11,90")
  end

  test "points to the settings and the customers while they are missing", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/buchhaltung/invoices/new")

    assert has_element?(view, ~s|#invoice-no-sender a[href="/settings/buchhaltung/invoices"]|)
    assert has_element?(view, ~s|#invoice-no-customers a[href="/buchhaltung/customers"]|)
    assert has_element?(view, "#invoice-write[disabled]")
  end

  test "lists no invoice of another user", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/buchhaltung/invoices")
    assert has_element?(view, "#invoices-empty")
  end
end
