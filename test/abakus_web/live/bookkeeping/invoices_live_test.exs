defmodule AbakusWeb.Bookkeeping.InvoicesLiveTest do
  use AbakusWeb.ConnCase

  import Phoenix.LiveViewTest
  import Abakus.BookkeepingFixtures
  import Abakus.DomainFixtures
  import Setzkasten.Test.Confirm

  alias Abakus.Bookkeeping
  alias Abakus.Bookkeeping.{InvoicePayments, Invoices}

  setup :register_and_log_in_user

  setup %{scope: scope} do
    business = account_fixture(kind: :tracking)
    {:ok, _ids} = Bookkeeping.put_business_accounts(scope, [business.id])
    fix_today(~D[2027-01-15])
    %{business: business}
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

  test "the owner confirms an incoming payment and can release it again", %{
    conn: conn,
    scope: scope,
    business: business
  } do
    sender_fixture(scope)
    invoice = invoice_fixture(scope, customer_fixture(scope))

    payment =
      transaction_fixture(%{
        account_id: business.id,
        date: ~D[2027-01-20],
        amount: invoice.total,
        payee_id: payee_fixture(name: "Muster & Söhne").id
      })

    {:ok, view, _html} = live(conn, ~p"/buchhaltung/invoices")
    row = "#invoice-#{invoice.id}"
    assert has_element?(view, row, "Zahlung eingegangen")

    asked = asked(view, "#{row}-pay-#{payment.id}")
    assert asked.question == "Zahlung bestätigen?"

    assert asked.text ==
             "Muster & Söhne hat am 20.01.2027 #{Abakus.Money.euros(99_068)} überwiesen."

    html = confirm_click(view, "#{row}-pay-#{payment.id}")
    assert html =~ "Rechnung 2027001 ist bezahlt."
    assert has_element?(view, row, "bezahlt am 20.01.2027")
    refute has_element?(view, "#{row}-pay-#{payment.id}")
    assert InvoicePayments.payments(scope, [invoice])[invoice.id].id == payment.id

    confirm_click(view, "#{row}-release", "Zahlung lösen?")
    assert has_element?(view, row, "Zahlung eingegangen")
    assert InvoicePayments.payments(scope, [invoice]) == %{}
  end

  test "shows an invoice without payment as open", %{conn: conn, scope: scope} do
    sender_fixture(scope)
    invoice = invoice_fixture(scope, customer_fixture(scope))

    {:ok, view, _html} = live(conn, ~p"/buchhaltung/invoices")

    assert has_element?(view, "#invoice-#{invoice.id}", "offen")
    assert has_element?(view, "#invoice-#{invoice.id}", "fällig 29.01.2027")
    refute has_element?(view, "#invoice-#{invoice.id}-release")
  end

  test "shows invoices from Lexoffice as paid, voided or open as they were there", %{
    conn: conn,
    scope: scope,
    business: business
  } do
    invoices = lexoffice_fixture(scope)
    transaction_fixture(%{account_id: business.id, date: ~D[2026-03-05], amount: 50_000})

    {:ok, view, _html} = live(conn, ~p"/buchhaltung/invoices")

    paid = "#invoice-#{invoices["2026124"].id}"
    assert has_element?(view, paid, "bezahlt am 05.03.2026")
    refute has_element?(view, paid, "Zahlung eingegangen")
    refute has_element?(view, paid, "offen")
    refute has_element?(view, "#{paid}-release")

    voided = "#invoice-#{invoices["2024102"].id}"
    assert has_element?(view, voided, "storniert")
    refute has_element?(view, voided, "offen")

    assert has_element?(view, "#invoice-#{invoices["2026125"].id}", "offen")
  end

  test "lists no invoice of another user", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/buchhaltung/invoices")
    assert has_element?(view, "#invoices-empty")
  end
end
