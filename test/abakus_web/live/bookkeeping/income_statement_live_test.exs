defmodule AbakusWeb.Bookkeeping.IncomeStatementLiveTest do
  use AbakusWeb.ConnCase

  import Phoenix.LiveViewTest
  import Abakus.BookkeepingFixtures
  import Abakus.DomainFixtures
  import AbakusWeb.PageText, only: [text: 2, flash: 2]

  alias Abakus.{Bookkeeping, Ledger}
  alias Abakus.Bookkeeping.{FakeElster, Filings}

  setup :register_and_log_in_user

  setup %{scope: scope} do
    kontist = account_fixture(name: "Kontist", kind: :tracking)
    {:ok, _ids} = Bookkeeping.put_business_accounts(scope, [kontist.id])
    fix_today(~D[2028-03-15])

    transaction =
      transaction_fixture(account_id: kontist.id, date: ~D[2027-01-20], amount: 119_000)

    {:ok, _lines} =
      Bookkeeping.save_tax_lines(scope, Bookkeeping.get_transaction(scope, transaction.id), %{
        "transaction" => %{"category" => "revenue", "vat" => "19"}
      })

    fixed_asset_fixture(scope, %{"purchased_on" => "2027-04-10", "net" => "2.400"})
    %{revenue: transaction}
  end

  defp cell(view, row, column), do: text(view, "#euer-#{row} > :nth-child(#{column})")

  test "shows the year to file next under the Kennzahlen of the Anlage EÜR", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/buchhaltung/euer")

    assert has_element?(view, "#side-bookkeeping-euer-sidebar[aria-current=page]")
    assert html =~ "Einnahmenüberschussrechnung 2027"
    assert cell(view, "112", 2) == "112"
    assert cell(view, "112", 3) == "1.000,00 €"
    assert cell(view, "140", 3) == "190,00 €"
    assert cell(view, "130", 3) == "600,00 €"
    assert cell(view, "income", 3) == "1.190,00 €"
    assert cell(view, "expenses", 3) == "600,00 €"
    assert cell(view, "profit", 3) == "590,00 €"
  end

  test "switches to the years before and after", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/buchhaltung/euer")

    view |> element("#euer-later") |> render_click()
    assert_patch(view, ~p"/buchhaltung/euer?year=2028")
    assert cell(view, "130", 3) == "800,00 €"
    refute has_element?(view, "#euer-112")

    view |> element("#euer-earlier") |> render_click()
    assert_patch(view, ~p"/buchhaltung/euer?year=2027")
    assert cell(view, "112", 3) == "1.000,00 €"
  end

  test "sends a year that is over to ELSTER with the certificate's PIN and locks it", c do
    elster_fixture(c.scope)
    FakeElster.serve()
    {:ok, view, _html} = live(c.conn, ~p"/buchhaltung/euer")

    view |> element("#euer-send") |> render_click()
    assert text(view, "#euer-send-modal") =~ "EÜR 2027 · Gewinn/Verlust 590,00 €"
    assert text(view, "#euer-send-test") =~ "ELSTER nimmt die EÜR an"

    view |> form("#euer-send-form", %{"pin" => "4711"}) |> render_submit()
    render_async(view)

    assert flash(view, :info) == "EÜR an ELSTER gesendet."
    refute has_element?(view, "#euer-send")
    assert text(view, "#euer-filing") =~ "Zeitraum ist festgeschrieben · Transferticket et-1"
    assert [%{pin: "4711", datenart_version: "EUER_2027"}] = FakeElster.submissions()
    assert Filings.locked?(c.scope, ~D[2027-06-30])

    view |> element("#euer-later") |> render_click()
    refute has_element?(view, "#euer-send")
    refute has_element?(view, "#euer-filing")
  end

  test "warns once the numbers of a sent year changed", c do
    elster_fixture(c.scope)
    FakeElster.serve()
    {:ok, _filing} = Filings.send_return(c.scope, {:euer, 2027}, "4711")

    {:ok, view, _html} = live(c.conn, ~p"/buchhaltung/euer")
    refute has_element?(view, "#euer-filing-changed")

    {:ok, _changed} = Ledger.update_transaction(c.scope, c.revenue, %{amount: 238_000})
    {:ok, view, _html} = live(c.conn, ~p"/buchhaltung/euer")
    assert text(view, "#euer-filing-changed") =~ "Die Zahlen weichen von der gesendeten EÜR ab"
  end

  test "says what the settings still lack for the EÜR", c do
    elster_fixture(c.scope)
    {:ok, _settings} = Bookkeeping.Invoices.save_settings(c.scope, %{"business_activity" => ""})
    {:ok, view, _html} = live(c.conn, ~p"/buchhaltung/euer")

    view |> element("#euer-send") |> render_click()

    assert text(view, "#euer-send-missing") =~ "Es fehlt: Art des Betriebs."
    refute has_element?(view, "#euer-send-form")
  end
end
