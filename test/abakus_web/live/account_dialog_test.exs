defmodule AbakusWeb.AccountDialogTest do
  use AbakusWeb.ConnCase

  import Phoenix.LiveViewTest
  import Abakus.DomainFixtures

  alias Abakus.Ledger

  setup :register_and_log_in_user

  test "the former account list opens the register of all accounts", %{conn: conn} do
    assert conn |> get(~p"/budget/accounts") |> redirected_to() == ~p"/budget/accounts/all"
  end

  describe "the sidebar" do
    setup do
      giro = account_fixture(name: "💶 Girokonto", kind: :checking)
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
      refute has_element?(view, "#side-add-account-sidebar")

      for entry <- ~w(budget depot-wealth all-accounts),
          do: assert(has_element?(view, "#side-#{entry}-dock"))

      refute has_element?(view, "#side-import-dock")

      refute has_element?(view, "#side-settings-dock")
      assert has_element?(view, ~s|nav.dock button[aria-haspopup=dialog]|, "Mehr")

      {:ok, settings, _html} = live(c.conn, ~p"/settings/access")

      refute has_element?(settings, "#side-account-#{c.giro.id}-sidebar")
    end

    test "on an account's register dock and rail mark Alle Konten", c do
      {:ok, view, _html} = live(c.conn, ~p"/budget/accounts/#{c.giro}")

      assert has_element?(view, ~s|#side-account-#{c.giro.id}-sidebar[aria-current="page"]|)
      assert has_element?(view, ~s|#side-all-accounts-dock[aria-current="true"]|)
      assert has_element?(view, ~s|#side-all-accounts-rail[aria-current="true"]|)
      refute has_element?(view, "nav.dock button.dock-active", "Mehr")
    end
  end

  test "without accounts Alle Konten still offers „Konto hinzufügen“", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/budget/accounts/all")

    assert has_element?(view, "#register-table", "Noch keine Konten")
    assert has_element?(view, "#register-table", "Lege mit „Konto hinzufügen“ ein Konto an")
    assert has_element?(view, "#register-cards", "Noch keine Konten")

    view |> element("#add-account") |> render_click()
    assert has_element?(view, "#account-dialog h2", "Konto hinzufügen")
  end

  defp submit(view, params), do: view |> form("#account-form", account: params) |> render_submit()

  defp open_edit(conn, account) do
    {:ok, view, _html} = live(conn, ~p"/budget/accounts/#{account}")
    view |> element("#edit-account") |> render_click()
    view
  end

  describe "adding" do
    test "opens from Alle Konten and goes to the new account's register", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/budget/accounts/all")
      refute has_element?(view, "#account-dialog")

      view |> element("#add-account") |> render_click()

      assert has_element?(view, "#account-dialog h2", "Konto hinzufügen")
      assert has_element?(view, "#account-dialog dialog #account_name")
      refute has_element?(view, "#close-account")
      refute has_element?(view, "#reopen-account")

      for kind <- ["Girokonto", "Sparkonto", "Bargeld", "Tracking"],
          do: assert(has_element?(view, "#account_kind option", kind))

      assert has_element?(view, "#account_balance")
      assert has_element?(view, "#account-kind-hint", "Tracking-Konten zählen nicht zum Budget.")
      assert has_element?(view, "#account-save", "Hinzufügen")

      submit(view, %{name: "🐷 Sparschwein", kind: "cash"})

      assert [account] = Ledger.list_accounts(budget_scope())
      assert %{name: "🐷 Sparschwein", kind: :cash, closed: false} = account
      assert Ledger.list_transactions(budget_scope(), account) == []

      path = ~p"/budget/accounts/#{account}"
      assert {^path, %{"info" => "Konto angelegt."}} = assert_redirect(view)
    end

    defp add(conn, params) do
      {:ok, view, _html} = live(conn, ~p"/budget/accounts/all")
      view |> element("#add-account") |> render_click()
      submit(view, params)
      view
    end

    defp account_named(name),
      do: Enum.find(Ledger.list_accounts(budget_scope()), &(&1.name == name))

    test "books the current balance today as „Anfangssaldo“", %{conn: conn} do
      fix_today(~D[2026-11-06])

      add(conn, %{name: "Haushaltskasse", kind: "cash", balance: "100+50"})

      assert [opening] = Ledger.list_transactions(budget_scope(), account_named("Haushaltskasse"))

      assert %{amount: 15_000, date: ~D[2026-11-06], cleared: :cleared, approved: true} = opening
      assert opening.payee.name == "Anfangssaldo"
      assert opening.category.internal

      add(conn, %{name: "Bausparvertrag", kind: "tracking", balance: "4.200,00"})

      assert [%{amount: 420_000, category_id: nil}] =
               Ledger.list_transactions(budget_scope(), account_named("Bausparvertrag"))

      add(conn, %{name: "Kreditkarte 2", kind: "checking", balance: "0,00"})
      assert Ledger.list_transactions(budget_scope(), account_named("Kreditkarte 2")) == []
    end

    test "refuses a balance that is no amount and keeps it", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/budget/accounts/all")
      view |> element("#add-account") |> render_click()

      assert view |> form("#account-form", account: %{balance: "60*2"}) |> render_change() =~
               "Ungültiger Betrag"

      submit(view, %{name: "Giro", kind: "checking", balance: "60*2"})

      assert has_element?(view, "#account_balance-error-0", "Ungültiger Betrag")
      assert has_element?(view, ~s|#account_balance[value="60*2"]|)
      assert Ledger.list_accounts(budget_scope()) == []

      submit(view, %{name: " ", kind: "checking", balance: "12"})
      assert has_element?(view, ~s|#account_balance[value="12"]|)
    end

    test "refuses a balance beyond the amounts' range", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/budget/accounts/all")
      view |> element("#add-account") |> render_click()

      submit(view, %{name: "Giro", kind: "checking", balance: "200000000000"})

      assert has_element?(view, "#account_balance-error-0", "Muss zwischen")
      assert Ledger.list_accounts(budget_scope()) == []

      assert view |> form("#account-form", account: %{balance: "300000000000"}) |> render_change() =~
               "Muss zwischen"

      submit(view, %{name: "Giro", kind: "checking", balance: "12"})
      assert [%{name: "Giro"}] = Ledger.list_accounts(budget_scope())
    end

    test "shows what is missing", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/budget/accounts/all")
      view |> element("#add-account") |> render_click()

      assert submit(view, %{name: " "}) =~ "Muss ausgefüllt werden"
      assert has_element?(view, "#account-dialog")
      assert Ledger.list_accounts(budget_scope()) == []
    end

    test "takes only name and kind from the form", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/budget/accounts/all")
      view |> element("#add-account") |> render_click()

      view
      |> element("#account-form")
      |> render_submit(%{
        "account" => %{"name" => "Giro", "kind" => "checking", "closed" => "true"}
      })

      assert [%{closed: false}] = Ledger.list_accounts(budget_scope())
    end

    test "cancelling closes the form and adds nothing", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/budget/accounts/all")

      view |> element("#add-account") |> render_click()
      view |> element("#account-cancel") |> render_click()
      refute has_element?(view, "#account-dialog")

      view |> element("#add-account") |> render_click()
      render_keydown(view, "close_account_dialog", %{"key" => "Escape"})
      refute has_element?(view, "#account-dialog")

      assert Ledger.list_accounts(budget_scope()) == []
    end
  end

  describe "editing" do
    test "the pencil opens the form over the register, which stays", %{conn: conn} do
      account = account_fixture(name: "Giro", kind: :checking)
      view = open_edit(conn, account)

      assert has_element?(view, "#account-dialog h2", "Konto bearbeiten")
      assert has_element?(view, ~s|#account_name[value="Giro"]|)
      assert has_element?(view, "#account-dialog #close-account", "Konto schließen")

      submit(view, %{name: "🏦 Gemeinschaftskonto", kind: "savings"})

      assert %{name: "🏦 Gemeinschaftskonto", kind: :savings} =
               Ledger.get_account!(budget_scope(), account.id)

      assert_patch(view, ~p"/budget/accounts/#{account}")
      refute has_element?(view, "#account-dialog")
      assert has_element?(view, "#flash-info", "Konto gespeichert")
      assert has_element?(view, "#register-title", "Gemeinschaftskonto")
      assert has_element?(view, "#register-meta", "Sparkonto")
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
      assert has_element?(view, "#account_name")
    end

    test "shows errors of an invalid change", %{conn: conn} do
      account = account_fixture(name: "Giro")
      view = open_edit(conn, account)

      assert view |> form("#account-form", account: %{name: ""}) |> render_change() =~
               "Muss ausgefüllt werden"

      assert submit(view, %{name: ""}) =~ "Muss ausgefüllt werden"
      assert has_element?(view, "#account-dialog")
      assert Ledger.get_account!(budget_scope(), account.id).name == "Giro"
    end

    test "an unknown account opens nothing", %{conn: conn} do
      account = account_fixture()
      {:ok, view, _html} = live(conn, ~p"/budget/accounts/#{account}")

      render_click(view, "open_account_dialog", %{"id" => Ecto.UUID.generate()})
      refute has_element?(view, "#account-dialog")
    end
  end

  describe "closing" do
    test "closes the account, which stays on screen; its register opens it again", %{conn: conn} do
      account = account_fixture(name: "Giro")
      transaction_fixture(account_id: account.id, amount: -1_200)
      view = open_edit(conn, account)

      assert has_element?(view, "#close-account", "Konto schließen …")
      confirm_click(view, "#close-account")

      assert Ledger.get_account!(budget_scope(), account.id).closed
      assert_patch(view, ~p"/budget/accounts/#{account}")
      refute has_element?(view, "#account-dialog")
      assert has_element?(view, "#flash-info", "Konto geschlossen")
      assert has_element?(view, "#register-meta", "Geschlossen")
      refute has_element?(view, "#side-account-#{account.id}-sidebar")

      assert has_element?(view, "#closed-banner", "Dieses Konto ist geschlossen.")
      refute has_element?(view, "#new-transaction")
      refute has_element?(view, "#new-transaction-fab")
      refute has_element?(view, "#file-import")
      refute has_element?(view, "#reconcile-open")
      render_click(view, "reconcile_open", %{})
      refute has_element?(view, "#reconcile-question")

      view |> element("#edit-account") |> render_click()
      refute has_element?(view, "#close-account")
      refute has_element?(view, "#account-dialog", "Wieder öffnen")
      view |> element("#account-cancel") |> render_click()

      view |> element("#reopen-account") |> render_click()

      refute Ledger.get_account!(budget_scope(), account.id).closed
      assert has_element?(view, "#flash-info", "Konto wieder geöffnet")
      refute has_element?(view, "#closed-banner")
      assert has_element?(view, "#side-account-#{account.id}-sidebar")
      assert has_element?(view, "#reconcile-open")
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

  describe "closed accounts" do
    test "are only behind Alle Konten's Ansicht menu, which opens them", %{conn: conn} do
      old = account_fixture(name: "Altes Sparbuch", kind: :savings, closed: true)
      transaction_fixture(account_id: old.id, amount: 300)
      account_fixture(name: "Giro")

      {:ok, view, _html} = live(conn, ~p"/budget/accounts/all")
      refute has_element?(view, "#side-account-#{old.id}-sidebar")
      assert has_element?(view, "#closed-accounts-item", "Geschlossene Konten (1) …")
      refute has_element?(view, "#closed-accounts")

      view |> element("#closed-accounts-item") |> render_click()

      assert has_element?(view, "#closed-accounts h2", "Geschlossene Konten")
      assert has_element?(view, "#closed-account-#{old.id}", "Altes Sparbuch")
      assert has_element?(view, "#closed-account-#{old.id}", "Sparkonto")
      assert has_element?(view, "#closed-account-#{old.id}", "3,00")

      {:ok, view, _html} =
        view
        |> element("#closed-account-#{old.id} a")
        |> render_click()
        |> follow_redirect(conn, ~p"/budget/accounts/#{old}")

      assert has_element?(view, "#register-title", "Altes Sparbuch")
      assert has_element?(view, "#closed-banner", "Dieses Konto ist geschlossen.")
      refute has_element?(view, "#closed-accounts-item")

      view |> element("#reopen-account") |> render_click()
      assert has_element?(view, "#side-account-#{old.id}-sidebar")

      {:ok, view, _html} = live(conn, ~p"/budget/accounts/all")
      refute has_element?(view, "#closed-accounts-item")
    end
  end
end
