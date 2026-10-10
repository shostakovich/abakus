defmodule AbakusWeb.RegisterLiveTest do
  use AbakusWeb.ConnCase

  import Phoenix.LiveViewTest
  import Abakus.DomainFixtures

  alias Abakus.{Categories, Ledger, Repo}
  alias Abakus.Ledger.Transaction

  setup :register_and_log_in_user

  setup do
    giro = account_fixture(name: "💶 Girokonto", kind: :checking, note: "Gehalt")
    savings = account_fixture(name: "🏦 Sparkonto", kind: :savings)
    depot = account_fixture(name: "📈 Depot", kind: :tracking, fed_by: :portfolio)
    groceries = category_fixture(name: "🛒 Lebensmittel")
    market = payee_fixture(name: "Frischmarkt")
    employer = payee_fixture(name: "Arbeitgeber")

    salary =
      transaction_fixture(
        account_id: giro.id,
        date: ~D[2026-10-01],
        amount: 324_000,
        payee_id: employer.id,
        category_id: Categories.ready_to_assign!().id,
        cleared: :cleared,
        memo: "Gehalt Oktober"
      )

    shopping =
      transaction_fixture(
        account_id: giro.id,
        date: ~D[2026-10-02],
        amount: -8_743,
        payee_id: market.id,
        category_id: groceries.id
      )

    imported =
      transaction_fixture(
        account_id: giro.id,
        date: ~D[2026-10-07],
        amount: -4_106,
        payee_id: market.id,
        category_id: groceries.id,
        cleared: :cleared,
        source: :file
      )

    {:ok, transfer} =
      Ledger.create_transaction(%{
        account_id: giro.id,
        date: ~D[2026-10-03],
        amount: -20_000,
        payee_id: savings.transfer_payee.id,
        memo: "Rücklagen"
      })

    old =
      transaction_fixture(
        account_id: giro.id,
        date: ~D[2026-09-22],
        amount: -31_280,
        payee_id: market.id,
        category_id: groceries.id,
        cleared: :reconciled
      )

    gain =
      transaction_fixture(
        account_id: depot.id,
        date: ~D[2026-10-08],
        amount: 112_500,
        cleared: :cleared
      )

    %{
      giro: giro,
      savings: savings,
      depot: depot,
      groceries: groceries,
      salary: salary,
      shopping: shopping,
      imported: imported,
      transfer: transfer,
      old: old,
      gain: gain
    }
  end

  defp reload(%{id: id}), do: Repo.get!(Transaction, id)

  describe "one account" do
    test "shows its transactions newest first with the balance equation", c do
      {:ok, view, _html} = live(c.conn, ~p"/accounts/#{c.giro}")

      assert has_element?(view, "h1#register-title", "💶 Girokonto")
      assert has_element?(view, "#register-meta", "Girokonto")
      assert has_element?(view, "#register-meta", "Gehalt")

      # 3.240,00 − 41,06 cleared − 312,80 reconciled; −87,43 − 200,00 uncleared
      assert has_element?(view, "#balance-cleared", "2.886,14 €")
      assert has_element?(view, "#balance-uncleared", "−287,43 €")
      assert has_element?(view, "#balance-working", "2.598,71 €")

      ids =
        view
        |> render()
        |> LazyHTML.from_fragment()
        |> LazyHTML.query("#register-table tbody tr[id]")
        |> LazyHTML.attribute("id")

      assert ids ==
               Enum.map([c.imported, c.transfer, c.shopping, c.salary, c.old], &"tx-#{&1.id}")

      assert has_element?(view, "#tx-#{c.salary.id}", "01.10.2026")
      assert has_element?(view, "#tx-#{c.salary.id}", "Arbeitgeber")
      assert has_element?(view, "#tx-#{c.salary.id}", "Einnahme: Zu verteilen")
      assert has_element?(view, "#tx-#{c.salary.id}", "Gehalt Oktober")
      assert has_element?(view, "#tx-#{c.salary.id} .app-in", "3.240,00")
      assert has_element?(view, "#tx-#{c.shopping.id}", "Lebensmittel")
      assert has_element?(view, "#tx-#{c.shopping.id} .app-out", "87,43")
      assert has_element?(view, "#tx-#{c.transfer.id}", "↔ 🏦 Sparkonto")
      refute has_element?(view, "#register-table th", "Konto")

      assert has_element?(view, "#tx-card-#{c.shopping.id}", "Frischmarkt")
      assert has_element?(view, "#tx-card-#{c.shopping.id}", "−87,43 €")
      assert has_element?(view, "#tx-card-#{c.salary.id}", "+3.240,00 €")
      refute has_element?(view, "#register-cards", "false")
      refute has_element?(view, "#tx-#{c.gain.id}")
    end

    test "the sidebar and the account list lead to it", c do
      {:ok, view, _html} = live(c.conn, ~p"/accounts/#{c.giro}")

      assert has_element?(
               view,
               ~s|aside #side-account-#{c.giro.id}.active[aria-current=page][href="/accounts/#{c.giro.id}"]|
             )

      refute has_element?(view, "aside #side-account-#{c.savings.id}.active")
      assert has_element?(view, ~s|a[href="/accounts/#{c.giro.id}/edit"]|)

      {:ok, list, _html} = live(c.conn, ~p"/accounts")
      assert has_element?(list, ~s|#account-#{c.giro.id}[href="/accounts/#{c.giro.id}"]|)
    end

    test "an account fed by another app offers no manual entry", c do
      {:ok, view, _html} = live(c.conn, ~p"/accounts/#{c.depot}")

      assert has_element?(view, "#feed-hint", "Depot-App")
      assert has_element?(view, "#balance-working", "1.125,00 €")
      refute has_element?(view, "#balance-cleared")

      shared = account_fixture(name: "👫 Geteilt", fed_by: :shared_expenses)
      {:ok, view, _html} = live(c.conn, ~p"/accounts/#{shared}")
      assert has_element?(view, "#feed-hint", "Ausgaben-App")
      assert has_element?(view, "#balance-cleared")

      {:ok, view, _html} = live(c.conn, ~p"/accounts/#{c.giro}")
      refute has_element?(view, "#feed-hint")

      # The form books in another account, unless none takes manual entries.
      assert {:ok, _view, _html} = live(c.conn, ~p"/accounts/#{c.depot}/transactions/new")

      for account <- [c.giro, c.savings],
          do: {:ok, _} = Ledger.update_account(account, %{closed: true})

      assert {:error, {:live_redirect, %{to: to}}} =
               live(c.conn, ~p"/accounts/#{c.depot}/transactions/new")

      assert to == ~p"/accounts/#{c.depot}"
    end

    test "without transactions it says so", c do
      {:ok, view, _html} = live(c.conn, ~p"/accounts/#{c.savings}")

      # The counterpart of the transfer is the only one.
      assert has_element?(view, "#balance-working", "200,00 €")

      empty = account_fixture(name: "Leer")
      {:ok, view, _html} = live(c.conn, ~p"/accounts/#{empty}")
      assert has_element?(view, "#register-table", "Noch keine Buchungen")
    end
  end

  describe "all accounts" do
    test "lists every account's transactions with Budget + Tracking = Gesamt", c do
      {:ok, view, _html} = live(c.conn, ~p"/accounts/all")

      assert has_element?(view, "h1#register-title", "Alle Konten")
      assert has_element?(view, "#register-table th", "Konto")
      assert has_element?(view, "#tx-#{c.gain.id}", "📈")
      assert has_element?(view, "#tx-card-#{c.gain.id}", "📈 Depot")
      refute has_element?(view, "#register-cards", "false")
      assert has_element?(view, "#tx-#{c.transfer.transfer_transaction_id}", "🏦")

      # Budget: 2.598,71 + 200,00 (savings, uncleared)
      assert has_element?(view, "#balance-cleared", "2.886,14 €")
      assert has_element?(view, "#balance-uncleared", "−87,43 €")
      assert has_element?(view, "#balance-working", "2.798,71 €")
      assert has_element?(view, "#balance-tracking", "1.125,00 €")
      assert has_element?(view, "#balance-total", "3.923,71 €")
      refute has_element?(view, "#running-toggle")
    end

    test "the account list leads to it and shows the total", c do
      {:ok, view, _html} = live(c.conn, ~p"/accounts")

      assert has_element?(view, "#accounts-total", "3.923,71 €")
      assert has_element?(view, ~s|a[href="/accounts/all"]|, "Alle Konten")
    end
  end

  describe "search and views" do
    test "search finds payee, category and memo and lives in the URL", c do
      {:ok, view, _html} = live(c.conn, ~p"/accounts/#{c.giro}")

      view |> form("#register-search", q: "rücklagen") |> render_change()

      assert_patch(view, ~p"/accounts/#{c.giro}?#{[q: "rücklagen"]}")
      assert has_element?(view, "#tx-#{c.transfer.id}")
      refute has_element?(view, "#tx-#{c.salary.id}")

      {:ok, view, _html} = live(c.conn, ~p"/accounts/#{c.giro}?q=zu+verteilen")
      assert has_element?(view, "#tx-#{c.salary.id}")
      refute has_element?(view, "#tx-#{c.shopping.id}")

      {:ok, view, _html} = live(c.conn, ~p"/accounts/#{c.giro}?q=nichts+davon")
      assert has_element?(view, "#register-table", "Keine Buchungen in dieser Ansicht")
    end

    test "views show what waits for approval or for the bank", c do
      {:ok, view, _html} = live(c.conn, ~p"/accounts/#{c.giro}")

      view |> element("#view-menu a", "Nicht abgeglichen") |> render_click()
      assert_patch(view, ~p"/accounts/#{c.giro}?filter=uncleared")
      assert has_element?(view, "#view-toggle", "nicht abgeglichen")
      assert has_element?(view, "#tx-#{c.shopping.id}")
      refute has_element?(view, "#tx-#{c.salary.id}")

      {:ok, view, _html} = live(c.conn, ~p"/accounts/#{c.giro}?filter=unapproved")
      assert has_element?(view, "#tx-#{c.imported.id}")
      refute has_element?(view, "#tx-#{c.shopping.id}")
    end

    test "the running balance shows for one account without view or search", c do
      {:ok, view, _html} = live(c.conn, ~p"/accounts/#{c.giro}")
      refute has_element?(view, "#register-table th", "Saldo")

      view |> element("#running-toggle") |> render_click()
      assert_patch(view, ~p"/accounts/#{c.giro}?running=1")

      assert has_element?(view, "#register-table th", "Saldo")
      assert has_element?(view, "#tx-#{c.imported.id} .app-run", "2.598,71")
      assert has_element?(view, "#tx-#{c.transfer.id} .app-run", "2.639,77")
      assert has_element?(view, "#tx-#{c.old.id} .app-run", "−312,80")

      {:ok, view, _html} = live(c.conn, ~p"/accounts/#{c.giro}?running=1&q=frischmarkt")
      refute has_element?(view, "#register-table th", "Saldo")
      assert has_element?(view, "#running-hint")

      {:ok, view, _html} = live(c.conn, ~p"/accounts/#{c.giro}?running=1&filter=uncleared")
      refute has_element?(view, "#register-table th", "Saldo")
    end
  end

  describe "flags" do
    test "the picker sets and clears a flag", c do
      {:ok, view, _html} = live(c.conn, ~p"/accounts/#{c.giro}")

      view |> element("#tx-#{c.shopping.id}-flag") |> render_click()
      assert has_element?(view, "#flag-menu button", "Lila")

      view |> element("#flag-menu-purple") |> render_click()
      assert reload(c.shopping).flag == :purple
      assert has_element?(view, "#tx-#{c.shopping.id}-flag.app-flag-purple")
      refute has_element?(view, "#flag-menu")

      view |> element("#tx-#{c.shopping.id}-flag") |> render_click()
      view |> element("#flag-menu-none") |> render_click()
      assert reload(c.shopping).flag == nil
    end

    test "a reconciled transaction asks first", c do
      {:ok, view, _html} = live(c.conn, ~p"/accounts/#{c.giro}")

      view |> element("#tx-#{c.old.id}-flag") |> render_click()
      assert has_element?(view, "#flag-menu-red[data-confirm]")
      view |> element("#flag-menu-red") |> render_click()

      assert reload(c.old).flag == :red
      assert reload(c.old).cleared == :reconciled
    end
  end

  describe "cleared state" do
    test "C toggles between uncleared and cleared", c do
      {:ok, view, _html} = live(c.conn, ~p"/accounts/#{c.giro}")

      view |> element("#tx-#{c.shopping.id}-cleared") |> render_click()
      assert reload(c.shopping).cleared == :cleared
      assert has_element?(view, "#tx-#{c.shopping.id}-cleared.is-cleared")
      assert has_element?(view, "#balance-cleared", "2.798,71 €")
      assert has_element?(view, "aside #side-account-#{c.giro.id}", "2.598,71")

      view |> element("#tx-card-#{c.shopping.id}-cleared") |> render_click()
      assert reload(c.shopping).cleared == :uncleared
    end

    test "a reconciled transaction asks before it is unlocked", c do
      {:ok, view, _html} = live(c.conn, ~p"/accounts/#{c.giro}")

      assert has_element?(view, "#tx-#{c.old.id}-cleared[data-confirm]")
      view |> element("#tx-#{c.old.id}-cleared") |> render_click()

      assert reload(c.old).cleared == :cleared
    end

    test "a reconciled transaction stays locked without the confirmation", c do
      {:ok, view, _html} = live(c.conn, ~p"/accounts/#{c.giro}")

      render_click(view, "toggle_cleared", %{"id" => "#{c.old.id}"})

      assert reload(c.old).cleared == :reconciled
      assert has_element?(view, "#flash-error", "Nicht geändert: Buchung ist abgeschlossen")
    end
  end

  describe "approval" do
    setup c do
      {:ok, waiting} = Ledger.update_transaction(c.imported, %{approved: false})

      {:ok, uncategorised} =
        Ledger.create_transaction(%{
          account_id: c.giro.id,
          date: ~D[2026-10-08],
          amount: -999,
          cleared: :cleared,
          source: :file
        })

      %{waiting: waiting, uncategorised: uncategorised}
    end

    test "the banner counts what waits and the rows are marked", c do
      {:ok, view, _html} = live(c.conn, ~p"/accounts/#{c.giro}")

      assert has_element?(view, "#unapproved-banner", "2 neue Buchungen zu bestätigen")
      assert has_element?(view, "tr#tx-#{c.waiting.id}.app-unapproved")
      refute has_element?(view, "tr#tx-#{c.shopping.id}.app-unapproved")
      assert has_element?(view, "#tx-#{c.uncategorised.id}", "Nicht kategorisiert")
      assert has_element?(view, "aside #side-account-#{c.giro.id} .badge", "2")

      view |> element("#show-unapproved") |> render_click()
      assert_patch(view, ~p"/accounts/#{c.giro}?filter=unapproved")
    end

    test "approves one on the desktop", c do
      {:ok, view, _html} = live(c.conn, ~p"/accounts/#{c.giro}")

      view |> element("#tx-#{c.waiting.id}-approve") |> render_click()

      assert reload(c.waiting).approved
      assert has_element?(view, "#unapproved-banner", "1 neue Buchung zu bestätigen")
      refute has_element?(view, "#tx-#{c.waiting.id}-approve")
    end

    test "approves one on the phone", c do
      {:ok, view, _html} = live(c.conn, ~p"/accounts/#{c.giro}")

      assert has_element?(view, "#tx-card-#{c.waiting.id}.app-unapproved-item")
      view |> element("#tx-card-#{c.waiting.id}-approve") |> render_click()

      assert reload(c.waiting).approved
      refute has_element?(view, "#tx-card-#{c.waiting.id}.app-unapproved-item")
    end

    test "approves all, match proposals stay open", c do
      {:ok, proposal} =
        Ledger.create_transaction(%{
          account_id: c.giro.id,
          date: ~D[2026-10-04],
          amount: -8_743,
          cleared: :cleared,
          source: :bank,
          matched_transaction_id: c.shopping.id
        })

      elsewhere =
        transaction_fixture(account_id: c.savings.id, approved: false, source: :api)

      {:ok, view, _html} = live(c.conn, ~p"/accounts/#{c.giro}")
      view |> element("#approve-all") |> render_click()

      assert reload(c.waiting).approved and reload(c.uncategorised).approved
      refute reload(proposal).approved
      assert reload(proposal).matched_transaction_id == c.shopping.id
      refute reload(elsewhere).approved
      refute has_element?(view, "#unapproved-banner")
      assert has_element?(view, "#flash-info", "2 bestätigt")

      {:ok, view, _html} = live(c.conn, ~p"/accounts/all")
      assert has_element?(view, "#unapproved-banner", "1 neue Buchung")
      view |> element("#approve-all") |> render_click()
      assert reload(elsewhere).approved
    end

    test "approve all asks first when a reconciled transaction waits", c do
      {:ok, _old} = Ledger.update_transaction(c.old, %{approved: false}, reconciled: :confirmed)
      {:ok, view, _html} = live(c.conn, ~p"/accounts/#{c.giro}")

      assert has_element?(view, "#approve-all[data-confirm]")
      view |> element("#approve-all") |> render_click()

      assert reload(c.old).approved
    end

    test "approves and categorises the selected ones", c do
      {:ok, view, _html} = live(c.conn, ~p"/accounts/#{c.giro}")
      refute has_element?(view, "#bulk")

      view |> element("#tx-#{c.waiting.id}-select") |> render_click()
      view |> element("#tx-#{c.uncategorised.id}-select") |> render_click()
      view |> element("#tx-#{c.transfer.id}-select") |> render_click()
      assert has_element?(view, "#bulk", "3 ausgewählt")
      assert has_element?(view, "tr#tx-#{c.waiting.id}.table-active")

      view
      |> form("#categorise-form", category_id: c.groceries.id)
      |> render_submit()

      assert reload(c.uncategorised).category_id == c.groceries.id
      # A transfer between budget accounts takes no category.
      assert reload(c.transfer).category_id == nil
      assert has_element?(view, "#flash-info", "2 kategorisiert")

      view |> element("#approve-selected") |> render_click()
      assert reload(c.waiting).approved and reload(c.uncategorised).approved
      refute has_element?(view, "#bulk")
    end

    test "approving the selected ones keeps the selection when nothing is approved", c do
      {:ok, _old} = Ledger.update_transaction(c.old, %{approved: false}, reconciled: :confirmed)
      {:ok, view, _html} = live(c.conn, ~p"/accounts/#{c.giro}")

      view |> element("#tx-#{c.shopping.id}-select") |> render_click()
      view |> element("#approve-selected") |> render_click()
      refute has_element?(view, "#flash-info", "0 bestätigt")
      assert has_element?(view, "#flash-info", "Keine der ausgewählten Buchungen wartet")
      assert has_element?(view, "#bulk", "1 ausgewählt")

      view |> element("#tx-#{c.waiting.id}-select") |> render_click()
      view |> element("#tx-#{c.old.id}-select") |> render_click()
      # Without the confirmation the reconciled one stays locked, and so do the others.
      render_click(view, "approve_selected", %{})
      assert has_element?(view, "#flash-error", "Nicht geändert: Buchung ist abgeschlossen")
      refute reload(c.waiting).approved
      assert has_element?(view, "#bulk", "3 ausgewählt")
    end

    test "selecting all takes the shown rows, and the selection can be cleared", c do
      {:ok, view, _html} = live(c.conn, ~p"/accounts/#{c.giro}?filter=unapproved")

      view |> element("#select-all") |> render_click()
      assert has_element?(view, "#bulk", "2 ausgewählt")

      view |> element("#clear-selection") |> render_click()
      refute has_element?(view, "#bulk")
    end

    test "categorising selected reconciled transactions asks first", c do
      {:ok, view, _html} = live(c.conn, ~p"/accounts/#{c.giro}")

      view |> element("#tx-#{c.old.id}-select") |> render_click()
      assert has_element?(view, "#categorise-form button[data-confirm]")
      # It is approved already, so approving it changes nothing.
      refute has_element?(view, "#approve-selected[data-confirm]")

      view
      |> form("#categorise-form", category_id: Categories.ready_to_assign!().id)
      |> render_submit()

      assert reload(c.old).category_id == Categories.ready_to_assign!().id
    end
  end
end
