defmodule AbakusWeb.LexofficeImportLiveTest do
  use AbakusWeb.ConnCase

  import Phoenix.LiveViewTest
  import Abakus.DomainFixtures
  import AbakusWeb.PageText, only: [text: 2]
  import ExUnit.CaptureLog

  alias Abakus.{Bookkeeping, FakePaperless, Paperless, Repo}
  alias Abakus.Bookkeeping.{FakeLexoffice, Invoices}

  @url "http://paperless.test"
  @key "lexoffice-key-4711"

  setup :register_and_log_in_user

  setup %{scope: scope} do
    kontist = account_fixture(name: "Kontist", kind: :tracking)
    {:ok, _ids} = Bookkeeping.put_business_accounts(scope, [kontist.id])
    {:ok, _connection} = Paperless.update_connection(scope, %{"url" => @url, "token" => "t"})
    FakePaperless.serve(%{@url => %{token: "t", documents: []}})
    FakeLexoffice.serve(@key)
    :ok
  end

  defp run_import(view, key) do
    view |> form("#lexoffice-form", lexoffice: %{token: key}) |> render_submit()
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

        assert text(view, "#lexoffice-result") =~ "3 Kunden und 4 Rechnungen übernommen."

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
    assert text(view, "#lexoffice-result") =~ "0 Kunden und 0 Rechnungen übernommen."
  end

  test "a refused key stops the import with Lexoffice's word", %{conn: conn, scope: scope} do
    {:ok, view, _html} = live(conn, ~p"/budget/lexoffice")

    run_import(view, "wrong")
    assert text(view, "#lexoffice-error") =~ "nimmt den API-Schlüssel nicht an"
    assert Invoices.list_customers(scope) == []
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
