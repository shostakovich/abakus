defmodule AbakusWeb.LexofficeImportLiveTest do
  use AbakusWeb.ConnCase

  import Phoenix.LiveViewTest
  import Abakus.DomainFixtures
  import AbakusWeb.PageText, only: [text: 2, flash: 2]
  import ExUnit.CaptureLog
  import Setzkasten.Test.Confirm

  alias Abakus.{Bookkeeping, FakePaperless, Paperless, Repo}
  alias Abakus.Bookkeeping.{Attachment, FakeLexoffice, Filings, Invoices, LexofficeReceipts}

  @url "http://paperless.test"
  @key "lexoffice-key-4711"

  setup :register_and_log_in_user

  setup %{scope: scope} do
    kontist = account_fixture(name: "Kontist", kind: :tracking)
    {:ok, _ids} = Bookkeeping.put_business_accounts(scope, [kontist.id])
    {:ok, _connection} = Paperless.update_connection(scope, %{"url" => @url, "token" => "t"})
    FakePaperless.serve(%{@url => %{token: "t", documents: []}})
    FakeLexoffice.serve(@key)
    fix_today(~D[2026-11-07])
    %{kontist: kontist}
  end

  defp run_import(view, key, quarter_filed \\ "none", year_filed \\ "none") do
    view
    |> form("#lexoffice-form",
      lexoffice: %{token: key, quarter_filed: quarter_filed, year_filed: year_filed}
    )
    |> render_submit()

    render_async(view)
  end

  defp stored_anywhere?(text) do
    %{rows: tables} = Repo.query!("SELECT name FROM sqlite_master WHERE type = 'table'")

    Enum.any?(tables, fn [table] ->
      %{rows: rows} = Repo.query!(~s(SELECT * FROM "#{table}"))

      Enum.any?(rows, fn row ->
        Enum.any?(row, &(is_binary(&1) and String.contains?(&1, text)))
      end)
    end)
  end

  defp debug_log(fun) do
    level = Logger.level()
    Logger.configure(level: :debug)

    try do
      capture_log([level: :debug], fun)
    after
      Logger.configure(level: level)
    end
  end

  test "the owner imports customers and invoices from Import & Sync with a key that is not stored",
       %{conn: conn, scope: scope} do
    {:ok, view, _html} = live(conn, ~p"/budget/lexoffice")
    assert has_element?(view, "#import-tabs a[href='/budget/lexoffice']", "Lexoffice")

    log =
      debug_log(fn ->
        run_import(view, @key)

        assert text(view, "#lexoffice-result") =~
                 "3 Kunden, 4 Rechnungen und 6 Belege übernommen. 6 Belege zu prüfen."

        assert text(view, "#lexoffice-skipped") =~
                 "2025110 nicht übernommen: Rechnung mit mehreren Steuersätzen"
      end)

    assert length(Invoices.list_invoices(scope)) == 4
    assert log =~ "HANDLE EVENT"
    refute log =~ @key
    refute stored_anywhere?(@key)
    refute render(view) =~ @key
  end

  test "a second run brings nothing new", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/budget/lexoffice")
    run_import(view, @key)

    run_import(view, @key)
    assert text(view, "#lexoffice-result") =~ "0 Kunden, 0 Rechnungen und 0 Belege übernommen."
  end

  test "the import asks for the last Voranmeldung and the last year filed and locks them", %{
    conn: conn,
    scope: scope
  } do
    {:ok, view, _html} = live(conn, ~p"/budget/lexoffice")

    assert has_element?(
             view,
             "#lexoffice_quarter_filed option[value='2026-3']",
             "3. Quartal 2026"
           )

    refute has_element?(view, "#lexoffice_quarter_filed option[value='2026-4']")
    refute has_element?(view, "#lexoffice_year_filed option[value='2026']")

    run_import(view, @key, "", "2024")

    assert text(view, "#lexoffice-error") =~
             "bis wann die Voranmeldungen und die Jahreserklärungen"

    run_import(view, @key, "2026-2", "")

    assert text(view, "#lexoffice-error") =~
             "bis wann die Voranmeldungen und die Jahreserklärungen"

    assert FakeLexoffice.requests() == []

    run_import(view, @key, "2026-2", "2024")

    assert text(view, "#lexoffice-result") =~
             "2020 bis 2024 sind festgeschrieben. Die Voranmeldungen bis zum 2. Quartal 2026 sind festgeschrieben."

    assert Filings.filed_elsewhere_through(scope, :vat_quarter) == {:vat_quarter, 2026, 2}
    assert Filings.filed_elsewhere_through(scope, :euer) == {:euer, 2024}

    {:ok, view, _html} = live(conn, ~p"/budget/lexoffice")
    assert has_element?(view, "#lexoffice_quarter_filed option[value='2026-2'][selected]")
    assert has_element?(view, "#lexoffice_year_filed option[value='2024'][selected]")
  end

  test "a receipt without a clear payment waits for review with its proposals", %{
    conn: conn,
    scope: scope,
    kontist: kontist
  } do
    payee = payee_fixture(name: "Büromarkt Nord")

    [first, second] =
      for _n <- 1..2,
          do:
            transaction_fixture(%{
              account_id: kontist.id,
              payee_id: payee.id,
              date: ~D[2024-05-02],
              amount: -1990
            })

    {:ok, view, _html} = live(conn, ~p"/budget/lexoffice")
    run_import(view, @key)

    [office] =
      for {receipt, _proposals} <- LexofficeReceipts.review(scope),
          receipt.number == "BN-2024-0512",
          do: receipt

    row = "#review-#{office.id}"
    assert text(view, row) =~ "Büromarkt Nord GmbH"
    assert text(view, row) =~ "bezahlt 02.05.2024 19,90 €"
    assert text(view, row) =~ "2 passende Buchungen"

    assert has_element?(
             view,
             "#{row}-attach-#{first.id}-menu-item",
             "02.05.2024 · Büromarkt Nord"
           )

    assert has_element?(view, "#{row}-attach-#{second.id}-menu-item")

    view |> element("#{row}-attach-#{first.id}-menu-item") |> render_click()
    assert flash(view, :info) == "Beleg BN-2024-0512 zugeordnet."
    refute has_element?(view, row)
    assert Repo.get_by!(Attachment, transaction_id: first.id).title == "Beleg BN-2024-0512"
  end

  test "opening the page attaches a waiting receipt that bank history imported later matches", %{
    conn: conn,
    scope: scope,
    kontist: kontist
  } do
    {:ok, view, _html} = live(conn, ~p"/budget/lexoffice")
    run_import(view, @key)
    assert LexofficeReceipts.review_count(scope) == 6

    internet =
      transaction_fixture(%{account_id: kontist.id, date: ~D[2025-03-03], amount: -11_900})

    {:ok, _view, _html} = live(conn, ~p"/budget/lexoffice")

    assert LexofficeReceipts.review_count(scope) == 5
    assert Repo.get_by!(Attachment, transaction_id: internet.id).title == "Beleg NT-88172"
  end

  test "a receipt on the review list is dismissed", %{conn: conn, scope: scope} do
    {:ok, view, _html} = live(conn, ~p"/budget/lexoffice")
    run_import(view, @key)
    [{receipt, []} | _rest] = LexofficeReceipts.review(scope)

    confirm_click(view, "#review-#{receipt.id}-dismiss-menu-item", "Keiner Buchung zuordnen?")
    refute has_element?(view, "#review-#{receipt.id}")
    assert LexofficeReceipts.review_count(scope) == 5
  end

  test "a refused key stops the import with Lexoffice's word", %{conn: conn, scope: scope} do
    {:ok, view, _html} = live(conn, ~p"/budget/lexoffice")

    run_import(view, "wrong")
    assert text(view, "#lexoffice-error") =~ "nimmt den API-Schlüssel nicht an"
    assert Invoices.list_customers(scope) == []
  end

  test "Lexoffice slowing the import down stops it with a word to try later", %{conn: conn} do
    stop_supervised!(FakeLexoffice)
    FakeLexoffice.serve(@key, %{"voucherlist" => {:error, :rate_limited}})
    {:ok, view, _html} = live(conn, ~p"/budget/lexoffice")

    run_import(view, @key)
    assert text(view, "#lexoffice-error") =~ "Lexoffice bremst gerade. Bitte später noch einmal."
    refute has_element?(view, "#lexoffice-result")
  end

  test "without Paperless it asks to connect it first", %{conn: conn, scope: scope} do
    {:ok, _connection} = Paperless.disconnect(scope)
    {:ok, view, _html} = live(conn, ~p"/budget/lexoffice")

    assert has_element?(view, "#lexoffice-no-paperless a[href='/settings/paperless']")
    assert has_element?(view, "#lexoffice-submit[disabled]")
  end

  test "without the Buchhaltung there is neither the tab nor the page", %{
    conn: conn,
    scope: scope
  } do
    {:ok, _ids} = Bookkeeping.put_business_accounts(scope, [])

    {:ok, view, _html} = live(conn, ~p"/budget/import")
    refute has_element?(view, "#import-tabs a[href='/budget/lexoffice']")

    assert_error_sent 404, fn -> get(conn, ~p"/budget/lexoffice") end
  end
end
