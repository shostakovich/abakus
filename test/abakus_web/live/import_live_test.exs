defmodule AbakusWeb.ImportLiveTest do
  use AbakusWeb.ConnCase

  import Phoenix.LiveViewTest
  import Abakus.DomainFixtures

  alias Abakus.Ledger

  setup :register_and_log_in_user

  setup do
    giro = account_fixture(name: "💶 Girokonto")
    account_fixture(name: "Geteilt", fed_by: :shared_expenses)
    account_fixture(name: "Depot", kind: :tracking, fed_by: :portfolio)
    account_fixture(name: "Altes Konto", closed: true)

    %{giro: giro}
  end

  defp upload(view, name) do
    content = File.read!("test/fixtures/ofx/#{name}")

    view
    |> file_input("#import-form", :file, [
      %{name: name, content: content, type: "application/octet-stream"}
    ])
    |> render_upload(name)
  end

  defp import_file(view, conn) do
    view |> element("#import-submit") |> render_click() |> follow_redirect(conn)
  end

  test "the sidebar and the register lead to the import", %{conn: conn, giro: giro} do
    {:ok, view, _html} = live(conn, ~p"/accounts/#{giro}")

    assert has_element?(view, ~s|aside a[href="/import"]|, "Import & Sync")
    assert has_element?(view, ~s|header a[href="/import"]|, "Import")
    assert has_element?(view, ~s|#file-import[href="/import"]|, "Datei-Import")

    {:ok, view, _html} = live(conn, ~p"/import")

    assert has_element?(view, "h1", "Import & Sync")
    assert has_element?(view, ~s|aside a.active[aria-current=page][href="/import"]|)
    assert has_element?(view, ~s|#import-form input[type=file][accept=".ofx,.qfx"]|)
    refute has_element?(view, "#import-preview")
  end

  test "an account fed by another app offers no file import", %{conn: conn} do
    shared = Enum.find(Ledger.list_accounts(), &(&1.name == "Geteilt"))
    {:ok, view, _html} = live(conn, ~p"/accounts/#{shared}")

    refute has_element?(view, "#file-import")
  end

  test "a fictional export imports without duplicates; an overlapping one adds only what is new",
       %{conn: conn, giro: giro} do
    {:ok, view, _html} = live(conn, ~p"/import")

    upload(view, "girokonto_2026-09.ofx")

    assert has_element?(view, "#import-preview", "girokonto_2026-09.ofx")
    assert has_element?(view, "#import-preview", "4 Buchungen · 01.09.2026–28.09.2026")
    assert has_element?(view, "#statement-0", "DE02100200300000004711")
    assert has_element?(view, "#statement-0", "BLZ 10020030")
    assert has_element?(view, "#statement-0-balance", "2.423,23 € am 30.09.2026")
    assert has_element?(view, "#statement-0-new", "4 neu")
    assert has_element?(view, "#statement-0-existing", "0 bereits vorhanden")
    assert has_element?(view, "#statement-0 tbody tr", "Bäckerei Korn")
    assert has_element?(view, "#statement-0 tbody tr", "Kartenzahlung")
    assert has_element?(view, "#statement-0 tbody tr", "−6,40 €")
    assert has_element?(view, "#statement-0 tbody tr", "+2.500,00 €")

    # The file's account is unknown, so the preview asks; fed and closed accounts are not offered.
    assert has_element?(view, "#statement-0-account option", "💶 Girokonto")
    refute has_element?(view, "#statement-0-account option", "Geteilt")
    refute has_element?(view, "#statement-0-account option", "Depot")
    refute has_element?(view, "#statement-0-account option", "Altes Konto")
    assert has_element?(view, "#import-submit[disabled]")

    view
    |> form("#statement-0-form", %{index: "0", account_id: giro.id})
    |> render_change()

    assert has_element?(view, "#import-submit:not([disabled])", "4 Buchungen importieren")

    {:ok, register, _html} = import_file(view, conn)

    assert render(register) =~
             "4 Buchungen importiert, zur Bestätigung in 💶 Girokonto. Banksaldo aus der Datei gemerkt."

    assert has_element?(register, "#register-title", "Girokonto")

    assert Enum.all?(
             Ledger.list_transactions(giro),
             &(not &1.approved and &1.cleared == :cleared)
           )

    {:ok, view, _html} = live(conn, ~p"/import")
    upload(view, "girokonto_2026-10.ofx")

    # The file's account is known now.
    assert has_element?(view, "#statement-0-account option[selected]", "💶 Girokonto")
    refute has_element?(view, "#statement-0-account option", "Konto wählen")
    assert has_element?(view, "#statement-0-new", "2 neu")
    assert has_element?(view, "#statement-0-existing", "2 bereits vorhanden")
    assert has_element?(view, "#statement-0 tbody tr.text-body-secondary", "Stadtbibliothek")
    assert has_element?(view, "#statement-0 tbody tr", "Stadtwerke & Co")

    {:ok, _register, _html} = import_file(view, conn)

    assert length(Ledger.list_transactions(giro)) == 6

    {:ok, view, _html} = live(conn, ~p"/import")
    upload(view, "girokonto_2026-10.ofx")

    assert has_element?(view, "#statement-0-new", "0 neu")
    assert has_element?(view, "#import-submit", "Importieren")

    {:ok, register, _html} = import_file(view, conn)

    assert render(register) =~ "Keine neuen Buchungen. Banksaldo aus der Datei gemerkt."
    assert length(Ledger.list_transactions(giro)) == 6
  end

  test "a linked file account can go into another account, which takes the link",
       %{conn: conn, giro: giro} do
    other = account_fixture(name: "Zweitkonto")
    {:ok, _giro} = Ledger.link_ofx_account(giro, "10020030", "DE02100200300000004711")
    {:ok, view, _html} = live(conn, ~p"/import")
    upload(view, "girokonto_2026-09.ofx")

    assert has_element?(view, "#statement-0-account option[selected]", "💶 Girokonto")
    assert has_element?(view, "#import-submit:not([disabled])")

    view |> form("#statement-0-form", %{index: "0", account_id: other.id}) |> render_change()

    assert has_element?(view, "#statement-0-account option[selected]", "Zweitkonto")

    {:ok, register, _html} = import_file(view, conn)

    assert render(register) =~ "4 Buchungen importiert, zur Bestätigung in Zweitkonto."
    assert length(Ledger.list_transactions(other)) == 4
    assert Ledger.list_transactions(giro) == []
    assert Ledger.get_account_by_ofx("10020030", "DE02100200300000004711").id == other.id
  end

  test "a file with two statements asks for an account each and leads to all accounts",
       %{conn: conn, giro: giro} do
    savings = account_fixture(name: "Tagesgeld", kind: :savings)
    {:ok, view, _html} = live(conn, ~p"/import")
    upload(view, "zwei_konten.ofx")

    assert has_element?(view, "#import-preview", "2 Buchungen · 02.10.2026–05.10.2026")
    assert has_element?(view, "#statement-0", "DE02100200300000005811")
    assert has_element?(view, "#statement-0-balance", "1.180,60 € am 08.10.2026")
    assert has_element?(view, "#statement-1", "DE02100200300000005822")
    refute has_element?(view, "#statement-1-balance")

    view |> form("#statement-0-form", %{index: "0", account_id: giro.id}) |> render_change()

    assert has_element?(view, "#import-submit[disabled]")

    view |> form("#statement-1-form", %{index: "1", account_id: giro.id}) |> render_change()
    view |> element("#import-submit") |> render_click()

    assert render(view) =~
             "Nicht importiert: Zwei Konten der Datei gehen nicht in dasselbe Konto."

    view |> form("#statement-1-form", %{index: "1", account_id: savings.id}) |> render_change()

    {:ok, register, _html} = import_file(view, conn)

    assert render(register) =~ "2 Buchungen importiert. Banksaldo aus der Datei gemerkt."
    assert has_element?(register, "#register-title", "Alle Konten")
    assert [%{amount: -2_340}] = Ledger.list_transactions(giro)
    assert [%{amount: 5_000}] = Ledger.list_transactions(savings)
  end

  test "a file over 5 MB says so", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/import")

    view
    |> file_input("#import-form", :file, [
      %{name: "gross.ofx", content: :binary.copy("x", 5_000_001), type: "application/x-ofx"}
    ])
    |> render_upload("gross.ofx")

    assert render(view) =~ "Die Datei ist größer als 5 MB."
    refute has_element?(view, "#import-preview")
  end

  test "a file that is no OFX says so", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/import")

    view
    |> file_input("#import-form", :file, [
      %{name: "umsaetze.csv", content: "Datum;Betrag", type: "text/csv"}
    ])
    |> render_upload("umsaetze.csv")

    assert render(view) =~ "Die Datei ist keine OFX- oder QFX-Datei."
    refute has_element?(view, "#import-preview")
  end

  test "discarding the preview imports nothing", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/import")
    upload(view, "girokonto_2026-09.ofx")

    view |> element("#import-discard") |> render_click()

    refute has_element?(view, "#import-preview")
    assert Ledger.list_transactions(:all) == []
  end

  test "an account that is not offered cannot be chosen", %{conn: conn} do
    shared = Enum.find(Ledger.list_accounts(), &(&1.name == "Geteilt"))
    {:ok, view, _html} = live(conn, ~p"/import")
    upload(view, "girokonto_2026-09.ofx")

    render_change(view, "choose_account", %{"index" => "0", "account_id" => "#{shared.id}"})
    render_click(view, "import", %{})

    assert has_element?(view, "#import-submit[disabled]")
    assert Ledger.list_transactions(:all) == []
  end

  test "a refused import names the transaction and keeps the preview", %{conn: conn, giro: giro} do
    {:ok, view, _html} = live(conn, ~p"/import")
    upload(view, "girokonto_2026-09.ofx")
    view |> form("#statement-0-form", %{index: "0", account_id: giro.id}) |> render_change()
    {:ok, _giro} = Ledger.update_account(giro, %{closed: true})

    view |> element("#import-submit") |> render_click()

    assert render(view) =~ "Nicht importiert: 💶 Girokonto nimmt keinen Datei-Import."
    assert has_element?(view, "#import-preview")
    assert Ledger.list_transactions(:all) == []
  end
end
