defmodule AbakusWeb.Bookkeeping.VatReturnFilingLiveTest do
  use AbakusWeb.ConnCase

  import Phoenix.LiveViewTest
  import Abakus.DomainFixtures
  import Abakus.BookkeepingFixtures
  import AbakusWeb.PageText, only: [text: 2, flash: 2]
  import ExUnit.CaptureLog

  alias Abakus.{Bookkeeping, Ledger, Repo, UsersFixtures}
  alias Abakus.Bookkeeping.{FakeElster, Filings}
  alias Abakus.Users.Scope

  setup :register_and_log_in_user

  setup %{scope: scope} do
    kontist = account_fixture(name: "Kontist", kind: :tracking)
    {:ok, _ids} = Bookkeeping.put_business_accounts(scope, [kontist.id])
    fix_today(~D[2027-04-15])
    revenue = transaction_fixture(account_id: kontist.id, date: ~D[2027-01-20], amount: 119_000)

    {:ok, _lines} =
      Bookkeeping.save_tax_lines(scope, Bookkeeping.get_transaction(scope, revenue.id), %{
        "transaction" => %{"category" => "revenue", "vat" => "19"}
      })

    %{revenue: revenue}
  end

  defp send_with_pin(view, pin) do
    view |> element("#vat-send") |> render_click()
    view |> form("#vat-send-form", %{"pin" => pin}) |> render_submit()
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

  test "asks for the certificate's PIN at every send and keeps it nowhere", c do
    elster_fixture(c.scope)
    FakeElster.serve()

    log =
      debug_log(fn ->
        {:ok, view, _html} = live(c.conn, ~p"/buchhaltung/vat")

        view |> element("#vat-send") |> render_click()
        assert has_element?(view, "#vat-send-modal input#vat-send-pin[type=password]")
        assert has_element?(view, "#vat-send-test")

        view |> form("#vat-send-form", %{"pin" => "geheim-4711"}) |> render_submit()
        render_async(view)

        assert flash(view, :info) == "Voranmeldung an ELSTER gesendet."
        refute has_element?(view, "#vat-send-modal")
        refute has_element?(view, "#vat-send")
        assert text(view, "#vat-filing") =~ "Zeitraum ist festgeschrieben · Transferticket et-1"
      end)

    assert [%{pin: "geheim-4711"}] = FakeElster.submissions()
    assert log =~ "HANDLE EVENT \"send\""
    refute log =~ "geheim-4711"
    refute stored_anywhere?("geheim-4711")
  end

  test "a failed send says why and locks nothing", c do
    elster_fixture(c.scope)
    FakeElster.serve(error: "ERiC-Fehler 610201101: Die PIN ist falsch.")
    {:ok, view, _html} = live(c.conn, ~p"/buchhaltung/vat")

    capture_log(fn -> send_with_pin(view, "0000") end)

    assert text(view, "#vat-send-error") =~ "ERiC-Fehler 610201101: Die PIN ist falsch."
    assert has_element?(view, "#vat-send-modal")
    assert Filings.sent(c.scope, {:vat_quarter, 2027, 1}) == nil
    refute has_element?(view, "#vat-filing")
  end

  test "says what the settings still lack instead of asking for the PIN", c do
    {:ok, view, _html} = live(c.conn, ~p"/buchhaltung/vat")
    view |> element("#vat-send") |> render_click()

    assert text(view, "#vat-send-missing") =~
             "Es fehlt: Name, Straße, PLZ, Ort, Steuernummer, Bundesland, ELSTER-Zertifikat."

    refute has_element?(view, "#vat-send-form")
  end

  test "offers to send only a period that is over", c do
    {:ok, view, _html} = live(c.conn, ~p"/buchhaltung/vat?period=2027-q2")
    refute has_element?(view, "#vat-send")

    {:ok, view, _html} = live(c.conn, ~p"/buchhaltung/vat?period=2027")
    refute has_element?(view, "#vat-send")
  end

  test "shows a sent quarter with its protocol, and once its numbers changed", c do
    elster_fixture(c.scope)
    FakeElster.serve()
    {:ok, filing} = Filings.send_return(c.scope, {:vat_quarter, 2027, 1}, "4711")

    {:ok, view, _html} = live(c.conn, ~p"/buchhaltung/vat")
    assert has_element?(view, "#vat-protocol[href='/buchhaltung/filings/#{filing.id}/protocol']")
    refute has_element?(view, "#vat-filing-changed")

    conn = get(c.conn, ~p"/buchhaltung/filings/#{filing.id}/protocol")
    assert response(conn, 200) == "%PDF-1.4 Protokoll"
    assert get_resp_header(conn, "content-type") == ["application/pdf"]

    {:ok, _changed} = Ledger.update_transaction(c.scope, c.revenue, %{amount: 238_000})
    {:ok, view, _html} = live(c.conn, ~p"/buchhaltung/vat")
    assert has_element?(view, "#vat-filing-changed")
  end

  test "keeps another user's protocol to them", c do
    other = Scope.for_user(UsersFixtures.user_fixture())
    elster_fixture(other)
    FakeElster.serve()
    {:ok, filing} = Filings.send_return(other, {:vat_quarter, 2027, 1}, "4711")

    assert c.conn |> get(~p"/buchhaltung/filings/#{filing.id}/protocol") |> response(404)
  end

  test "sends the Umsatzsteuererklärung of a year that is over", c do
    elster_fixture(c.scope)
    FakeElster.serve()
    {:ok, view, _html} = live(c.conn, ~p"/buchhaltung/vat?period=2026")

    view |> element("#vat-send") |> render_click()

    assert text(view, "#vat-send-modal") =~
             "Umsatzsteuererklärung 2026 · Abschlusszahlung / Erstattung 0,00 €"

    assert text(view, "#vat-send-modal") =~ "Nach dem Senden ist das Jahr festgeschrieben."

    view |> form("#vat-send-form", %{"pin" => "4711"}) |> render_submit()
    render_async(view)

    assert flash(view, :info) == "Umsatzsteuererklärung an ELSTER gesendet."
    assert has_element?(view, "#vat-filing")
    assert [%{datenart_version: "USt_2026"}] = FakeElster.submissions()

    view |> element("#vat-period a", "Q4") |> render_click()
    assert has_element?(view, "#vat-send")
    refute has_element?(view, "#vat-filing")
  end
end
