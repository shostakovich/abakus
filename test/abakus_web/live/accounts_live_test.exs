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

    test "says how many transactions of an account wait for approval", c do
      transaction_fixture(account_id: c.cash.id, amount: -100, approved: false)
      {:ok, view, _html} = live(c.conn, ~p"/budget/accounts")

      assert has_element?(view, "#account-#{c.cash.id} .badge", "1 zu bestätigen")
      refute has_element?(view, "#account-#{c.giro.id} .badge")
    end

    test "groups the accounts into budget and tracking with working and cleared balance", c do
      {:ok, view, _html} = live(c.conn, ~p"/budget/accounts")

      assert has_element?(view, "h1", "Konten")
      assert has_element?(view, ~s|nav a[aria-current=page][href="/budget/accounts/all"]|)
      refute has_element?(view, ~s|aside a[href="/budget/accounts"]|)

      assert has_element?(view, "#group-budget h2", "Budget")
      assert has_element?(view, "#group-budget-balance", "2.437,51 €")
      assert has_element?(view, "#account-#{c.giro.id}", "💶 Girokonto")
      assert has_element?(view, "#account-#{c.giro.id}", "Girokonto\u2060\u00A0· Gehalt")
      assert has_element?(view, "#account-#{c.giro.id}-balance", "2.450,01 €")
      assert has_element?(view, "#account-#{c.giro.id}-cleared", "2.500,00 €")
      assert has_element?(view, "#account-#{c.cash.id}-balance.text-error-ink", "−12,50 €")
      assert has_element?(view, "#account-#{c.cash.id}-cleared", "0,00 €")
      assert has_element?(view, "#group-tracking h2", "Tracking")
      assert has_element?(view, "#account-#{c.depot.id}-cleared", "10.000,00 €")
      assert has_element?(view, "#group-closed h2", "Geschlossen")
      assert has_element?(view, "#accounts-total", "12.440,51 €")

      assert view
             |> render()
             |> LazyHTML.from_document()
             |> LazyHTML.query("#accounts > li[id]")
             |> LazyHTML.attribute("id") == [
               "group-budget",
               "account-#{c.giro.id}",
               "account-#{c.cash.id}",
               "group-tracking",
               "account-#{c.depot.id}",
               "group-closed",
               "account-#{c.old.id}"
             ]

      assert has_element?(
               view,
               ~s|#account-#{c.giro.id} a[href="/budget/accounts/#{c.giro.id}"]|
             )
    end

    test "the sidebar lists the open accounts with their working balance", c do
      {:ok, view, _html} = live(c.conn, ~p"/budget")

      assert has_element?(view, "aside li.menu-title", ~r/Budgetkonten\s*2\.437,51\s€/u)
      assert has_element?(view, "aside li.menu-title", ~r/Trackingkonten\s*10\.000,00\s€/u)
      refute has_element?(view, "aside li.menu-title", "Geschlossen")
      assert has_element?(view, "#side-account-#{c.giro.id}-sidebar", "Girokonto")
      assert has_element?(view, "#side-account-#{c.giro.id}-sidebar", "💶")
      assert has_element?(view, "#side-account-#{c.giro.id}-sidebar", "2.450,01 €")

      assert has_element?(
               view,
               "#side-account-#{c.cash.id}-sidebar .text-sidebar-negative",
               "−12,50"
             )

      assert has_element?(view, "#side-account-#{c.depot.id}-sidebar", "10.000,00 €")
      refute has_element?(view, "#side-account-#{c.old.id}-sidebar")
      refute has_element?(view, "#side-account-#{c.giro.id}-rail")
      refute has_element?(view, "#side-account-#{c.giro.id}-dock")
      assert has_element?(view, "button#side-add-account-sidebar", "Konto hinzufügen")
      refute has_element?(view, "#side-add-account-dock")

      for entry <- ~w(budget depot-wealth all-accounts),
          do: assert(has_element?(view, "#side-#{entry}-dock"))

      refute has_element?(view, "#side-import-dock")

      refute has_element?(view, "#side-settings-dock")
      assert has_element?(view, ~s|nav.dock button[aria-haspopup=dialog]|, "Mehr")

      assert has_element?(
               view,
               "aside li.menu-title:has(+ li #side-account-#{c.depot.id}-sidebar) ~ li #side-add-account-sidebar"
             )

      {:ok, settings, _html} = live(c.conn, ~p"/settings/access")

      assert has_element?(settings, "#side-account-#{c.giro.id}-sidebar:not([data-phx-link])")
    end

    test "on an account's register dock and rail mark Alle Konten", c do
      {:ok, view, _html} = live(c.conn, ~p"/budget/accounts/#{c.giro}")

      assert has_element?(view, ~s|#side-account-#{c.giro.id}-sidebar[aria-current="page"]|)
      assert has_element?(view, ~s|#side-all-accounts-dock[aria-current="true"]|)
      assert has_element?(view, ~s|#side-all-accounts-rail[aria-current="true"]|)
      refute has_element?(view, "nav.dock button.dock-active", "Mehr")
    end
  end

  test "without accounts the list says so", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/budget/accounts")

    assert has_element?(view, "main p", "Noch keine Konten")
    assert has_element?(view, "main #add-account", "Konto hinzufügen")
    refute has_element?(view, "#accounts")
  end

  defp submit(view, params), do: view |> form("#account-form", account: params) |> render_submit()

  defp open_edit(conn, account) do
    {:ok, view, _html} = live(conn, ~p"/budget/accounts/#{account}")
    view |> element("#edit-account") |> render_click()
    view
  end

  describe "adding" do
    test "opens over the account list and goes to the new account's register", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/budget/accounts")
      refute has_element?(view, "#account-dialog")

      view |> element("#add-account") |> render_click()

      assert has_element?(view, "#account-dialog h2", "Konto hinzufügen")
      assert has_element?(view, "#account-dialog dialog #account_name")
      refute has_element?(view, "#close-account")
      refute has_element?(view, "#reopen-account")

      for kind <- ["Girokonto", "Sparkonto", "Bargeld", "Tracking"],
          do: assert(has_element?(view, "#account_kind option", kind))

      submit(view, %{name: "🐷 Sparschwein", kind: "cash", note: "Im Regal"})

      assert [account] = Ledger.list_accounts()
      assert %{name: "🐷 Sparschwein", kind: :cash, note: "Im Regal", closed: false} = account

      path = ~p"/budget/accounts/#{account}"
      assert {^path, %{"info" => "Konto angelegt."}} = assert_redirect(view)
    end

    test "opens from the sidebar over any page", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/budget")

      view |> element("#side-add-account-sidebar") |> render_click()
      assert has_element?(view, "#account-dialog h2", "Konto hinzufügen")

      submit(view, %{name: "Giro", kind: "checking"})
      assert [account] = Ledger.list_accounts()
      path = ~p"/budget/accounts/#{account}"
      assert {^path, _flash} = assert_redirect(view)

      {:ok, settings, _html} = live(conn, ~p"/settings/access")
      settings |> element("#side-add-account-sidebar") |> render_click()
      assert has_element?(settings, "#account-dialog h2", "Konto hinzufügen")
    end

    test "shows what is missing", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/budget/accounts")
      view |> element("#add-account") |> render_click()

      assert submit(view, %{name: " "}) =~ "Muss ausgefüllt werden"
      assert has_element?(view, "#account-dialog")
      assert Ledger.list_accounts() == []
    end

    test "takes only name, kind and note from the form", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/budget/accounts")
      view |> element("#add-account") |> render_click()

      view
      |> element("#account-form")
      |> render_submit(%{
        "account" => %{"name" => "Giro", "kind" => "checking", "closed" => "true"}
      })

      assert [%{closed: false}] = Ledger.list_accounts()
    end

    test "cancelling closes the form and adds nothing", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/budget/accounts")

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

      assert_patch(view, ~p"/budget/accounts/#{account}")
      refute has_element?(view, "#account-dialog")
      assert has_element?(view, "#flash-info", "Konto gespeichert")
      assert has_element?(view, "#register-title", "Gemeinschaftskonto")
      assert has_element?(view, "#register-meta", "Für beide")
      assert has_element?(view, "#side-account-#{account.id}-sidebar", "Gemeinschaftskonto")
    end

    test "keeps the register's view", %{conn: conn} do
      account = account_fixture(name: "Giro")
      {:ok, view, _html} = live(conn, ~p"/budget/accounts/#{account}?filter=unapproved")

      view |> element("#edit-account") |> render_click()
      submit(view, %{name: "Giro 2"})

      assert_patch(view, ~p"/budget/accounts/#{account}?filter=unapproved")
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
               "Muss ausgefüllt werden"

      assert submit(view, %{name: ""}) =~ "Muss ausgefüllt werden"
      assert has_element?(view, "#account-dialog")
      assert Ledger.get_account!(account.id).name == "Giro"
    end

    test "an unknown account opens nothing", %{conn: conn} do
      account = account_fixture()
      {:ok, view, _html} = live(conn, ~p"/budget/accounts/#{account}")

      render_click(view, "open_account_dialog", %{"id" => "#{account.id + 1_000}"})
      refute has_element?(view, "#account-dialog")
    end
  end

  describe "closing" do
    test "closes the account and opens it again", %{conn: conn} do
      account = account_fixture(name: "Giro")
      view = open_edit(conn, account)

      refute has_element?(view, "#reopen-account")
      confirm_click(view, "#close-account")

      assert Ledger.get_account!(account.id).closed
      assert_patch(view, ~p"/budget/accounts/#{account}")
      refute has_element?(view, "#account-dialog")
      assert has_element?(view, "#flash-info", "Konto geschlossen")
      assert has_element?(view, "#register-meta", "Geschlossen")
      refute has_element?(view, "#side-account-#{account.id}-sidebar")

      view |> element("#edit-account") |> render_click()
      assert has_element?(view, "#account-closed", "geschlossen")
      refute has_element?(view, "#close-account")
      view |> element("#reopen-account") |> render_click()

      refute Ledger.get_account!(account.id).closed
      assert has_element?(view, "#flash-info", "Konto wieder geöffnet")
      assert has_element?(view, "#side-account-#{account.id}-sidebar")
    end

    test "asks first and names a balance that is left", %{conn: conn} do
      empty = account_fixture(name: "Leer")
      full = account_fixture(name: "Voll")
      transaction_fixture(account_id: full.id, amount: 1_200)

      view = open_edit(conn, empty)

      assert %{
               question: "Konto „Leer“ schließen?",
               text: "Du kannst es später wieder öffnen.",
               label: "Schließen"
             } = asked(view, "#close-account")

      view = open_edit(conn, full)

      assert %{
               question: "Konto „Voll“ schließen?",
               text: "Es hat noch einen Saldo von 12,00 €."
             } = asked(view, "#close-account")
    end
  end
end
