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
      assert has_element?(view, ~s|header nav a.active[aria-current=page][href="/accounts"]|)
      refute has_element?(view, ~s|aside a[href="/accounts"]|)

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
               ~s|#account-#{c.giro.id}[href="/accounts/#{c.giro.id}"]|
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
      assert has_element?(view, "aside #side-add-account", "Konto hinzufügen")

      {:ok, settings, _html} = live(c.conn, ~p"/users/settings")

      assert has_element?(
               settings,
               ~s|aside a[href="/accounts/#{c.giro.id}"]:not([data-phx-link])|
             )
    end
  end

  test "without accounts the list says so", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/accounts")

    assert has_element?(view, "p", "Noch keine Konten")
    assert has_element?(view, "main #add-account", "Konto hinzufügen")
  end

  defp submit(view, params), do: view |> form("#account-form", account: params) |> render_submit()

  defp open_edit(conn, account) do
    {:ok, view, _html} = live(conn, ~p"/accounts/#{account}")
    view |> element("#edit-account") |> render_click()
    view
  end

  describe "adding" do
    test "opens over the account list and goes to the new account's register", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/accounts")
      refute has_element?(view, "#account-dialog")

      view |> element("#add-account") |> render_click()

      assert has_element?(view, "#account-dialog h2", "Konto hinzufügen")
      assert has_element?(view, "#account-dialog .app-sheet #account_name")
      refute has_element?(view, "#close-account")
      refute has_element?(view, "#reopen-account")

      for kind <- ["Girokonto", "Sparkonto", "Bargeld", "Tracking"],
          do: assert(has_element?(view, "#account_kind option", kind))

      submit(view, %{name: "🐷 Sparschwein", kind: "cash", note: "Im Regal"})

      assert [account] = Ledger.list_accounts()
      assert %{name: "🐷 Sparschwein", kind: :cash, note: "Im Regal", closed: false} = account

      path = ~p"/accounts/#{account}"
      assert {^path, %{"info" => "Konto angelegt."}} = assert_redirect(view)
    end

    test "opens from the sidebar over any page", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("aside #side-add-account") |> render_click()
      assert has_element?(view, "#account-dialog h2", "Konto hinzufügen")

      submit(view, %{name: "Giro", kind: "checking"})
      assert [account] = Ledger.list_accounts()
      path = ~p"/accounts/#{account}"
      assert {^path, _flash} = assert_redirect(view)

      {:ok, settings, _html} = live(conn, ~p"/users/settings")
      settings |> element("aside #side-add-account") |> render_click()
      assert has_element?(settings, "#account-dialog h2", "Konto hinzufügen")
    end

    test "shows what is missing", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/accounts")
      view |> element("#add-account") |> render_click()

      assert submit(view, %{name: " "}) =~ "muss ausgefüllt werden"
      assert has_element?(view, "#account-dialog")
      assert Ledger.list_accounts() == []
    end

    test "takes only name, kind and note from the form", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/accounts")
      view |> element("#add-account") |> render_click()

      view
      |> element("#account-form")
      |> render_submit(%{
        "account" => %{"name" => "Giro", "kind" => "checking", "closed" => "true"}
      })

      assert [%{closed: false}] = Ledger.list_accounts()
    end

    test "cancelling closes the form and adds nothing", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/accounts")

      view |> element("#add-account") |> render_click()
      view |> element("#account-cancel") |> render_click()
      refute has_element?(view, "#account-dialog")

      view |> element("#add-account") |> render_click()
      render_keydown(view, "close_account_dialog", %{"key" => "Escape"})
      refute has_element?(view, "#account-dialog")

      assert Ledger.list_accounts() == []
    end
  end

  describe "editing" do
    test "the pencil opens the form over the register, which stays", %{conn: conn} do
      account = account_fixture(name: "Giro", kind: :checking)
      view = open_edit(conn, account)

      assert has_element?(view, "#account-dialog h2", "Konto bearbeiten")
      assert has_element?(view, ~s|#account_name[value="Giro"]|)
      assert has_element?(view, "#account-dialog #close-account", "Konto schließen")

      submit(view, %{name: "🏦 Gemeinschaftskonto", kind: "savings", note: "Für beide"})

      assert %{name: "🏦 Gemeinschaftskonto", kind: :savings, note: "Für beide"} =
               Ledger.get_account!(account.id)

      assert_patch(view, ~p"/accounts/#{account}")
      refute has_element?(view, "#account-dialog")
      assert has_element?(view, "#flash-info", "Konto gespeichert")
      assert has_element?(view, "#register-title", "Gemeinschaftskonto")
      assert has_element?(view, "#register-meta", "Für beide")
      assert has_element?(view, "aside #side-account-#{account.id}", "Gemeinschaftskonto")
    end

    test "keeps the register's view", %{conn: conn} do
      account = account_fixture(name: "Giro")
      {:ok, view, _html} = live(conn, ~p"/accounts/#{account}?filter=unapproved")

      view |> element("#edit-account") |> render_click()
      submit(view, %{name: "Giro 2"})

      assert_patch(view, ~p"/accounts/#{account}?filter=unapproved")
    end

    test "offers only kinds on the account's side of the budget", %{conn: conn} do
      budget = account_fixture(kind: :savings)
      tracking = account_fixture(kind: :tracking)

      view = open_edit(conn, budget)
      assert has_element?(view, "#account_kind option", "Bargeld")
      refute has_element?(view, "#account_kind option", "Tracking")

      view = open_edit(conn, tracking)
      refute has_element?(view, "#account_kind")
      assert has_element?(view, "#account_note")
    end

    test "shows errors of an invalid change", %{conn: conn} do
      account = account_fixture(name: "Giro")
      view = open_edit(conn, account)

      assert view |> form("#account-form", account: %{name: ""}) |> render_change() =~
               "muss ausgefüllt werden"

      assert submit(view, %{name: ""}) =~ "muss ausgefüllt werden"
      assert has_element?(view, "#account-dialog")
      assert Ledger.get_account!(account.id).name == "Giro"
    end

    test "an unknown account opens nothing", %{conn: conn} do
      account = account_fixture()
      {:ok, view, _html} = live(conn, ~p"/accounts/#{account}")

      render_click(view, "open_account_dialog", %{"id" => "#{account.id + 1_000}"})
      refute has_element?(view, "#account-dialog")
    end
  end

  describe "closing" do
    test "closes the account and opens it again", %{conn: conn} do
      account = account_fixture(name: "Giro")
      view = open_edit(conn, account)

      refute has_element?(view, "#reopen-account")
      view |> element("#close-account") |> render_click()

      assert Ledger.get_account!(account.id).closed
      assert_patch(view, ~p"/accounts/#{account}")
      refute has_element?(view, "#account-dialog")
      assert has_element?(view, "#flash-info", "Konto geschlossen")
      assert has_element?(view, "#register-meta", "Geschlossen")
      refute has_element?(view, "aside #side-account-#{account.id}")

      view |> element("#edit-account") |> render_click()
      assert has_element?(view, "#account-closed", "geschlossen")
      refute has_element?(view, "#close-account")
      view |> element("#reopen-account") |> render_click()

      refute Ledger.get_account!(account.id).closed
      assert has_element?(view, "#flash-info", "Konto wieder geöffnet")
      assert has_element?(view, "aside #side-account-#{account.id}")
    end

    test "asks first and names a balance that is left", %{conn: conn} do
      empty = account_fixture(name: "Leer")
      full = account_fixture(name: "Voll")
      transaction_fixture(account_id: full.id, amount: 1_200)

      view = open_edit(conn, empty)
      assert has_element?(view, ~s|#close-account[data-confirm="Konto „Leer“ schließen?"]|)

      view = open_edit(conn, full)

      assert has_element?(
               view,
               ~s|#close-account[data-confirm="Konto „Voll“ schließen? Es hat noch einen Saldo von 12,00 €."]|
             )
    end
  end
end
