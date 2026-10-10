defmodule AbakusWeb.AccountsLiveTest do
  use AbakusWeb.ConnCase

  import Phoenix.LiveViewTest
  import Abakus.DomainFixtures

  alias Abakus.Ledger

  setup :register_and_log_in_user

  describe "the account list" do
    setup do
      giro = account_fixture(name: "💶 Girokonto", kind: :checking, note: "Gehalt")
      cash = account_fixture(name: "👛 Bargeld", kind: :cash)
      depot = account_fixture(name: "📈 Depot", kind: :tracking)
      old = account_fixture(name: "Altes Sparbuch", kind: :savings, closed: true)

      transaction_fixture(account_id: giro.id, amount: 250_000, cleared: :cleared)
      transaction_fixture(account_id: giro.id, amount: -4_999, cleared: :uncleared)
      transaction_fixture(account_id: cash.id, amount: -1_250, cleared: :uncleared)
      transaction_fixture(account_id: depot.id, amount: 1_000_000, cleared: :reconciled)
      transaction_fixture(account_id: old.id, amount: 300, cleared: :cleared)

      %{giro: giro, cash: cash, depot: depot, old: old}
    end

    test "groups the accounts into budget and tracking with working and cleared balance", c do
      {:ok, view, _html} = live(c.conn, ~p"/accounts")

      assert has_element?(view, "h1", "Konten")
      assert has_element?(view, ~s|aside nav a.active[aria-current=page][href="/accounts"]|)

      assert has_element?(view, "#group-budget h2", "Budget")
      assert has_element?(view, "#group-budget-balance", "2.437,51 €")
      assert has_element?(view, "#group-budget #account-#{c.giro.id}", "💶 Girokonto")
      assert has_element?(view, "#account-#{c.giro.id}", "Girokonto · Gehalt")
      assert has_element?(view, "#account-#{c.giro.id}-balance", "2.450,01 €")
      assert has_element?(view, "#account-#{c.giro.id}-cleared", "2.500,00 €")
      assert has_element?(view, "#account-#{c.cash.id}-balance.app-neg", "−12,50 €")
      assert has_element?(view, "#account-#{c.cash.id}-cleared", "0,00 €")

      assert has_element?(view, "#group-tracking h2", "Tracking")
      assert has_element?(view, "#group-tracking #account-#{c.depot.id}", "📈 Depot")
      assert has_element?(view, "#account-#{c.depot.id}-cleared", "10.000,00 €")

      assert has_element?(view, "#group-closed h2", "Geschlossen")
      assert has_element?(view, "#group-closed #account-#{c.old.id}", "Altes Sparbuch")

      assert has_element?(
               view,
               ~s|#account-#{c.giro.id}[href="/accounts/#{c.giro.id}/edit"]|
             )
    end

    test "the sidebar lists the open accounts with their working balance", c do
      {:ok, view, _html} = live(c.conn, ~p"/")

      assert has_element?(view, "aside #side-group-budget", "2.437,51")
      assert has_element?(view, "aside #side-group-tracking", "10.000,00")
      refute has_element?(view, "aside #side-group-closed")
      assert has_element?(view, "aside #side-account-#{c.giro.id}", "Girokonto")
      assert has_element?(view, "aside #side-account-#{c.giro.id}", "2.450,01")
      assert has_element?(view, "aside #side-account-#{c.cash.id} .app-neg", "−12,50")
      assert has_element?(view, "aside #side-account-#{c.depot.id}", "10.000,00")
      refute has_element?(view, "aside #side-account-#{c.old.id}")
      assert has_element?(view, ~s|aside a[href="/accounts/new"]|, "Konto hinzufügen")

      {:ok, settings, _html} = live(c.conn, ~p"/users/settings")

      assert has_element?(
               settings,
               ~s|aside a[href="/accounts/#{c.giro.id}/edit"]:not([data-phx-link])|
             )
    end
  end

  test "without accounts the list says so", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/accounts")

    assert has_element?(view, "p", "Noch keine Konten")
    assert has_element?(view, ~s|main a[href="/accounts/new"]|, "Konto hinzufügen")
  end

  describe "creating" do
    test "adds the account and lists it", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/accounts/new")

      assert has_element?(view, "h1", "Konto hinzufügen")

      for kind <- ["Girokonto", "Sparkonto", "Bargeld", "Tracking"],
          do: assert(has_element?(view, "#account_kind option", kind))

      {:ok, view, _html} =
        view
        |> form("#account-form",
          account: %{name: "🐷 Sparschwein", kind: "cash", note: "Im Regal"}
        )
        |> render_submit()
        |> follow_redirect(conn, ~p"/accounts")

      assert [account] = Ledger.list_accounts()
      assert %{name: "🐷 Sparschwein", kind: :cash, note: "Im Regal", closed: false} = account
      assert has_element?(view, "#flash-info", "Konto angelegt")
      assert has_element?(view, "#group-budget #account-#{account.id}", "Sparschwein")
      assert has_element?(view, "aside #side-account-#{account.id}", "Sparschwein")
    end

    test "shows what is missing", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/accounts/new")

      html = view |> form("#account-form", account: %{name: " "}) |> render_submit()

      assert html =~ "muss ausgefüllt werden"
      assert Ledger.list_accounts() == []
    end

    test "takes only name, kind and note from the form", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/accounts/new")

      view
      |> render_submit("save", %{
        "account" => %{"name" => "Giro", "kind" => "checking", "closed" => "true"}
      })

      assert [%{closed: false}] = Ledger.list_accounts()
    end
  end

  describe "editing" do
    test "changes name, kind and note", %{conn: conn} do
      account = account_fixture(name: "Giro", kind: :checking)
      {:ok, view, _html} = live(conn, ~p"/accounts/#{account}/edit")

      assert has_element?(view, "h1", "Konto bearbeiten")
      assert has_element?(view, ~s|#account_name[value="Giro"]|)

      {:ok, view, _html} =
        view
        |> form("#account-form",
          account: %{name: "🏦 Gemeinschaftskonto", kind: "savings", note: "Für beide"}
        )
        |> render_submit()
        |> follow_redirect(conn, ~p"/accounts")

      assert %{name: "🏦 Gemeinschaftskonto", kind: :savings, note: "Für beide"} =
               Ledger.get_account!(account.id)

      assert has_element?(view, "#flash-info", "Konto gespeichert")
      assert has_element?(view, "#account-#{account.id}", "Gemeinschaftskonto")
    end

    test "offers only kinds on the account's side of the budget", %{conn: conn} do
      budget = account_fixture(kind: :savings)
      tracking = account_fixture(kind: :tracking)

      {:ok, view, _html} = live(conn, ~p"/accounts/#{budget}/edit")
      assert has_element?(view, "#account_kind option", "Bargeld")
      refute has_element?(view, "#account_kind option", "Tracking")

      {:ok, view, _html} = live(conn, ~p"/accounts/#{tracking}/edit")
      assert has_element?(view, "#account_kind option", "Tracking")
      refute has_element?(view, "#account_kind option", "Girokonto")
    end

    test "shows errors of an invalid change", %{conn: conn} do
      account = account_fixture(name: "Giro")
      {:ok, view, _html} = live(conn, ~p"/accounts/#{account}/edit")

      assert view |> form("#account-form", account: %{name: ""}) |> render_change() =~
               "muss ausgefüllt werden"

      assert view |> form("#account-form", account: %{name: ""}) |> render_submit() =~
               "muss ausgefüllt werden"

      assert Ledger.get_account!(account.id).name == "Giro"
    end
  end

  describe "closing" do
    test "closes the account and opens it again", %{conn: conn} do
      account = account_fixture(name: "Giro")
      {:ok, view, _html} = live(conn, ~p"/accounts/#{account}/edit")

      refute has_element?(view, "#reopen-account")

      {:ok, view, _html} =
        view
        |> element("#close-account")
        |> render_click()
        |> follow_redirect(conn, ~p"/accounts")

      assert Ledger.get_account!(account.id).closed
      assert has_element?(view, "#flash-info", "Konto geschlossen")
      assert has_element?(view, "#group-closed #account-#{account.id}")
      refute has_element?(view, "aside #side-account-#{account.id}")

      {:ok, view, _html} = live(conn, ~p"/accounts/#{account}/edit")
      refute has_element?(view, "#close-account")

      {:ok, view, _html} =
        view
        |> element("#reopen-account")
        |> render_click()
        |> follow_redirect(conn, ~p"/accounts")

      refute Ledger.get_account!(account.id).closed
      assert has_element?(view, "#flash-info", "Konto wieder geöffnet")
      assert has_element?(view, "#group-budget #account-#{account.id}")
    end

    test "asks first and names a balance that is left", %{conn: conn} do
      empty = account_fixture(name: "Leer")
      full = account_fixture(name: "Voll")
      transaction_fixture(account_id: full.id, amount: 1_200)

      {:ok, view, _html} = live(conn, ~p"/accounts/#{empty}/edit")
      assert has_element?(view, ~s|#close-account[data-confirm="Konto „Leer“ schließen?"]|)

      {:ok, view, _html} = live(conn, ~p"/accounts/#{full}/edit")

      assert has_element?(
               view,
               ~s|#close-account[data-confirm="Konto „Voll“ schließen? Es hat noch einen Saldo von 12,00 €."]|
             )
    end
  end
end
