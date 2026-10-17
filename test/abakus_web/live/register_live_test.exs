defmodule AbakusWeb.RegisterLiveTest do
  use AbakusWeb.ConnCase

  import Phoenix.LiveViewTest
  import Abakus.DomainFixtures
  import Ecto.Query, only: [from: 2]

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
        category_id: Categories.ready_to_assign!(budget_scope()).id,
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
      Ledger.create_transaction(budget_scope(), %{
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
      {:ok, view, _html} = live(c.conn, ~p"/budget/accounts/#{c.giro}")

      assert has_element?(view, "h1 #register-title", "💶 Girokonto")
      assert has_element?(view, "#register-meta", "Girokonto")
      assert has_element?(view, "#register-meta", "Gehalt")

      # 3.240,00 − 41,06 cleared − 312,80 reconciled; −87,43 − 200,00 uncleared
      assert has_element?(view, "#balance-cleared", "2.886,14 €")
      assert has_element?(view, "#balance-uncleared", "−287,43 €")
      refute has_element?(view, "#balance-uncleared.text-error-ink")
      assert has_element?(view, "#balance-working", "2.598,71 €")
      refute has_element?(view, "#register-balances .text-success-ink")

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
      assert has_element?(view, "#tx-card-#{c.shopping.id}", "−87,43 €")
      assert has_element?(view, "#tx-card-#{c.salary.id}", "+3.240,00 €")
      refute has_element?(view, "#register-cards", "false")
      refute has_element?(view, "#tx-#{c.gain.id}")
    end

    test "the sidebar and the account list lead to it", c do
      {:ok, view, _html} = live(c.conn, ~p"/budget/accounts/#{c.giro}")

      assert has_element?(
               view,
               sidebar_link("/budget/accounts/#{c.giro.id}") <> "[aria-current=page]"
             )

      refute has_element?(
               view,
               sidebar_link("/budget/accounts/#{c.savings.id}") <> "[aria-current=page]"
             )

      assert has_element?(view, ~s|#edit-account[phx-value-id="#{c.giro.id}"]|)
    end

    test "an account fed by the Depot offers no manual entry", c do
      {:ok, view, _html} = live(c.conn, ~p"/budget/accounts/#{c.depot}")

      assert has_element?(view, "#feed-hint", "Wert kommt aus dem Depot")
      assert has_element?(view, "#balance-working", "1.125,00 €")
      refute has_element?(view, "#balance-cleared")

      shared = account_fixture(name: "👫 Geteilt", fed_by: :shared_expenses)
      {:ok, view, _html} = live(c.conn, ~p"/budget/accounts/#{shared}")
      assert has_element?(view, "#feed-hint", "aus der Kasse")
      assert has_element?(view, "#balance-cleared")

      refute has_element?(view, "#new-transaction")

      {:ok, view, _html} = live(c.conn, ~p"/budget/accounts/#{c.giro}")
      refute has_element?(view, "#feed-hint")
      assert has_element?(view, "#new-transaction")

      # All accounts book in one that takes manual entries, as long as there is one.
      {:ok, view, _html} = live(c.conn, ~p"/budget/accounts/all")
      assert has_element?(view, "#new-transaction")

      for account <- [c.giro, c.savings],
          do: {:ok, _} = Ledger.update_account(budget_scope(), account, %{closed: true})

      {:ok, view, _html} = live(c.conn, ~p"/budget/accounts/all")
      refute has_element?(view, "#new-transaction")
      refute has_element?(view, "#new-transaction-fab")
    end

    test "an account fed by the Depot offers no reconcile", c do
      {:ok, view, _html} = live(c.conn, ~p"/budget/accounts/#{c.depot}")

      refute has_element?(view, "#reconcile-open")
      render_click(view, "reconcile_open", %{})
      refute has_element?(view, "#reconcile-question")
    end

    test "keeps account, date, amount and payee of the Depot's value change", c do
      {:ok, change} =
        Ledger.create_transaction(budget_scope(), %{
          account_id: c.depot.id,
          date: ~D[2026-10-09],
          amount: 5_000,
          payee_name: "Wertänderung",
          cleared: :cleared,
          approved: true,
          source: :depot
        })

      {:ok, view, _html} = live(c.conn, ~p"/budget/accounts/#{c.depot}")
      view |> element("#tx-#{change.id} td.app-payee") |> render_click()
      view |> element("#tx-#{change.id} td.app-payee") |> render_click()

      assert has_element?(view, "#tx-depot", "bucht das Depot")

      for field <- ~w(tx-date tx-outflow tx-inflow) do
        assert has_element?(view, "##{field}[disabled]")
      end

      assert has_element?(view, "#tx-payee-combobox input[disabled]")
      refute has_element?(view, "#tx-delete")

      view
      |> element("#tx-form")
      |> render_submit(%{
        "transaction" => %{
          "memo" => "Kursplus",
          "inflow" => "99",
          "date" => "2026-01-01",
          "payee_new" => "Jemand"
        }
      })

      assert %{amount: 5_000, date: ~D[2026-10-09], memo: "Kursplus", account_id: depot_id} =
               change = Repo.preload(reload(change), :payee)

      assert depot_id == c.depot.id
      assert change.payee.name == "Wertänderung"

      render_click(view, "clear_selection", %{})
      render_click(view, "select", %{"id" => "#{change.id}"})
      render_click(view, "delete_selected", %{})
      assert has_element?(view, "#flash-error", "bucht das Depot")

      render_click(view, "clear_selection", %{})
      view |> element("#tx-#{change.id} td.app-payee") |> render_click()
      view |> element("#tx-#{change.id} td.app-payee") |> render_click()
      view |> with_target("#tx-editor") |> render_click("delete", %{})
      assert has_element?(view, "#tx-error", "bucht das Depot")

      refute reload(change).deleted_at
    end

    test "without transactions it says so", c do
      {:ok, view, _html} = live(c.conn, ~p"/budget/accounts/#{c.savings}")

      # The counterpart of the transfer is the only one.
      assert has_element?(view, "#balance-working", "200,00 €")

      empty = account_fixture(name: "Leer")
      {:ok, view, _html} = live(c.conn, ~p"/budget/accounts/#{empty}")
      assert has_element?(view, "#register-table", "Noch keine Buchungen")
    end
  end

  describe "all accounts" do
    test "lists every account's transactions with Budget + Tracking = Gesamt", c do
      {:ok, view, _html} = live(c.conn, ~p"/budget/accounts/all")

      assert has_element?(view, "h1 #register-title", "Alle Konten")

      assert has_element?(
               view,
               sidebar_link("/budget/accounts/all") <> "[aria-current=page]",
               "Alle Konten"
             )

      assert has_element?(
               view,
               ~s|#app-shell > nav[aria-label=Hauptnavigation] a[aria-current=page][href="/budget/accounts/all"]|,
               "Alle Konten"
             )

      assert has_element?(view, "#register-table th", "Konto")
      assert has_element?(view, "#tx-#{c.gain.id}", "📈")
      assert has_element?(view, "#tx-card-#{c.gain.id}", "📈 Depot")
      refute has_element?(view, "#register-cards", "false")
      assert has_element?(view, "#tx-#{c.transfer.transfer_transaction_id}", "🏦")

      # Budget: 2.598,71 + 200,00 (savings, uncleared)
      assert has_element?(view, "#balance-cleared", "2.886,14 €")
      assert has_element?(view, "#balance-uncleared", "−87,43 €")
      assert has_element?(view, "#balance-working", "2.798,71 €")
      assert has_element?(view, "#balance-tracking", "1.125,00 €")
      assert has_element?(view, "#balance-total", "3.923,71 €")
      assert has_element?(view, "#balance-working[phx-hook]")
      refute has_element?(view, "#balance-total[phx-hook]")
      refute has_element?(view, "#running-toggle")
    end
  end

  describe "header and columns" do
    test "the header has three rows and Abgleichen as its one primary button", c do
      Repo.update_all(from(a in Ledger.Account, where: a.id == ^c.giro.id),
        set: [last_reconciled_at: ~U[2026-10-05 10:00:00Z]]
      )

      {:ok, view, _html} = live(c.conn, ~p"/budget/accounts/#{c.giro}")
      document = view |> render() |> LazyHTML.from_fragment()

      assert has_element?(view, "#register-meta svg")
      assert has_element?(view, "#register-meta", "Abgeglichen am 05.10.2026")
      assert has_element?(view, "#reconcile-open.btn-primary", "Abgleichen")
      assert document |> LazyHTML.query("#register .btn-primary") |> Enum.count() == 1
      refute has_element?(view, "#register-back")

      assert has_element?(view, "#register-balances-line", "Gebucht")
      assert has_element?(view, "#register-balances-line", "Vorgemerkt")
      assert has_element?(view, "#register-balances-line", "Arbeitssaldo")

      for id <- ~w(new-transaction file-import register-search view-menu),
          do: assert(has_element?(view, "#register-toolbar ##{id}"))
    end

    test "all accounts: the budget accounts' equation, tracking, the total and „Konto hinzufügen“",
         c do
      {:ok, view, _html} = live(c.conn, ~p"/budget/accounts/all")

      assert has_element?(view, "#register-balances", "Budgetkonten")
      assert has_element?(view, "#register-balances-line", "Budgetkonten")
      assert has_element?(view, "#register-balances-line", "Gesamt")
      assert has_element?(view, "#register #add-account", "Konto hinzufügen")
      refute has_element?(view, "#register .btn-primary")
    end

    test "the approve button shows only while something waits", c do
      {:ok, view, _html} = live(c.conn, ~p"/budget/accounts/#{c.savings}")

      refute has_element?(view, "#approve-all")
      refute has_element?(view, "#approve-all-item")
      refute has_element?(view, "#accept-all-matches")
    end

    test "columns come from a colgroup, memo and status are columns of their own", c do
      {:ok, view, _html} = live(c.conn, ~p"/budget/accounts/#{c.giro}")
      document = view |> render() |> LazyHTML.from_fragment()

      assert document |> LazyHTML.query("#register-table colgroup col") |> Enum.count() ==
               document |> LazyHTML.query("#register-table thead th") |> Enum.count()

      assert has_element?(view, "#register-table th.app-memo-col", "Memo")
      assert has_element?(view, "#tx-#{c.salary.id} td.app-memo-col", "Gehalt Oktober")
      refute has_element?(view, "#tx-#{c.salary.id} td.app-payee", "Gehalt Oktober")

      assert has_element?(view, "#register-table thead th:last-child.app-c-col svg")
      assert has_element?(view, "#register-table thead th.app-c-col .sr-only", "Gebucht")
      refute has_element?(view, "#register-table thead th.app-c-col", "C")

      assert has_element?(
               view,
               "#tx-#{c.shopping.id} td:last-child #tx-#{c.shopping.id}-cleared svg"
             )
    end

    test "the view menu hides and shows the memo column on this device", c do
      {:ok, view, _html} = live(c.conn, ~p"/budget/accounts/#{c.giro}")

      assert has_element?(view, "#memo-toggle .app-memo-hide", "Memo ausblenden")
      assert has_element?(view, "#memo-toggle .app-memo-show", "Memo zeigen")
      assert view |> element("#memo-toggle") |> render() =~ "abakus:toggle-memo"

      {:ok, view, _html} = live(c.conn, ~p"/budget/accounts/all")
      assert has_element?(view, "#memo-toggle")
    end

    test "an opened row has its memo input in the memo column", c do
      {:ok, view, _html} = live(c.conn, ~p"/budget/accounts/#{c.giro}")

      view |> element("#tx-#{c.shopping.id} td.app-payee") |> render_click()
      view |> element("#tx-#{c.shopping.id} td.app-payee") |> render_click()

      assert has_element?(view, "#tx-editor .app-edit-grid > .app-memo-col #tx-memo")
    end
  end

  describe "search and views" do
    test "search finds payee, category and memo and lives in the URL", c do
      {:ok, view, _html} = live(c.conn, ~p"/budget/accounts/#{c.giro}")

      view |> form("#register-search", q: "rücklagen") |> render_change()

      assert_patch(view, ~p"/budget/accounts/#{c.giro}?#{[q: "rücklagen"]}")
      assert has_element?(view, "#tx-#{c.transfer.id}")
      refute has_element?(view, "#tx-#{c.salary.id}")

      {:ok, view, _html} = live(c.conn, ~p"/budget/accounts/#{c.giro}?q=zu+verteilen")
      assert has_element?(view, "#tx-#{c.salary.id}")
      refute has_element?(view, "#tx-#{c.shopping.id}")

      {:ok, view, _html} = live(c.conn, ~p"/budget/accounts/#{c.giro}?q=nichts+davon")
      assert has_element?(view, "#register-table", "Keine Buchungen in dieser Ansicht")
    end

    test "views show what waits for approval or for the bank", c do
      {:ok, view, _html} = live(c.conn, ~p"/budget/accounts/#{c.giro}")

      view |> element("#view-menu a", "Vorgemerkt") |> render_click()
      assert_patch(view, ~p"/budget/accounts/#{c.giro}?filter=uncleared")
      assert has_element?(view, "#view-toggle", "vorgemerkt")
      assert has_element?(view, "#tx-#{c.shopping.id}")
      refute has_element?(view, "#tx-#{c.salary.id}")

      {:ok, view, _html} = live(c.conn, ~p"/budget/accounts/#{c.giro}?filter=unapproved")
      assert has_element?(view, "#tx-#{c.imported.id}")
      refute has_element?(view, "#tx-#{c.shopping.id}")
    end

    test "the running balance shows for one account without view or search", c do
      {:ok, view, _html} = live(c.conn, ~p"/budget/accounts/#{c.giro}")
      refute has_element?(view, "#register-table th", "Saldo")

      view |> element("#running-toggle") |> render_click()
      assert_patch(view, ~p"/budget/accounts/#{c.giro}?running=1")

      assert has_element?(view, "#register-table th", "Saldo")
      assert has_element?(view, "#tx-#{c.imported.id} .app-run", "2.598,71")
      assert has_element?(view, "#tx-#{c.transfer.id} .app-run", "2.639,77")
      assert has_element?(view, "#tx-#{c.old.id} .app-run", "−312,80")

      {:ok, view, _html} = live(c.conn, ~p"/budget/accounts/#{c.giro}?running=1&q=frischmarkt")
      refute has_element?(view, "#register-table th", "Saldo")
      assert has_element?(view, "#running-hint")

      {:ok, view, _html} = live(c.conn, ~p"/budget/accounts/#{c.giro}?running=1&filter=uncleared")
      refute has_element?(view, "#register-table th", "Saldo")
    end
  end

  test "has no flags", c do
    {:ok, view, _html} = live(c.conn, ~p"/budget/accounts/#{c.giro}")

    refute has_element?(view, "#tx-#{c.shopping.id}-flag")
    refute render(view) =~ "Markierung"
    refute :flag in Transaction.__schema__(:fields)
  end

  describe "cleared state" do
    test "speaks a bank's words: vorgemerkt, gebucht, abgeglichen", c do
      {:ok, view, _html} = live(c.conn, ~p"/budget/accounts/#{c.giro}")

      assert has_element?(view, "#register-balances", "Gebucht")
      assert has_element?(view, "#register-balances", "Vorgemerkt")
      assert has_element?(view, "#register-balances", "Arbeitssaldo")

      assert has_element?(
               view,
               ~s|#tx-#{c.shopping.id}-cleared[aria-label="Vorgemerkt, umschalten"]|
             )

      assert has_element?(view, ~s|#tx-#{c.salary.id}-cleared[aria-label="Gebucht, umschalten"]|)
      assert has_element?(view, ~s|#tx-#{c.old.id}-cleared[aria-label="Abgeglichen, entsperren"]|)
      refute render(view) =~ ~r/nicht abgeglichen|abgeschlossen/i
    end

    test "C toggles between uncleared and cleared", c do
      {:ok, view, _html} = live(c.conn, ~p"/budget/accounts/#{c.giro}")

      view |> element("#tx-#{c.shopping.id}-cleared") |> render_click()
      assert reload(c.shopping).cleared == :cleared

      assert has_element?(
               view,
               ~s|#tx-#{c.shopping.id}-cleared[aria-label="Gebucht, umschalten"][title="Gebucht"]|
             )

      assert has_element?(view, "#balance-cleared", "2.798,71 €")
      assert has_element?(view, sidebar_link("/budget/accounts/#{c.giro.id}"), "2.598,71")

      view |> element("#tx-card-#{c.shopping.id}-cleared") |> render_click()
      assert reload(c.shopping).cleared == :uncleared
    end

    test "a reconciled transaction asks before it is unlocked", c do
      {:ok, view, _html} = live(c.conn, ~p"/budget/accounts/#{c.giro}")

      assert asked(view, "#tx-#{c.old.id}-cleared").label == "Entsperren"

      confirm_click(
        view,
        "#tx-#{c.old.id}-cleared",
        "Diese Buchung ist abgeglichen. Entsperren?"
      )

      assert reload(c.old).cleared == :cleared
    end

    test "a reconciled transaction stays locked without the confirmation", c do
      {:ok, view, _html} = live(c.conn, ~p"/budget/accounts/#{c.giro}")

      render_click(view, "toggle_cleared", %{"id" => "#{c.old.id}"})

      assert reload(c.old).cleared == :reconciled
      assert has_element?(view, "#flash-error", "Nicht geändert: Buchung ist abgeglichen")
    end
  end

  describe "approval" do
    setup c do
      {:ok, waiting} = Ledger.update_transaction(budget_scope(), c.imported, %{approved: false})

      {:ok, uncategorised} =
        Ledger.create_transaction(budget_scope(), %{
          account_id: c.giro.id,
          date: ~D[2026-10-08],
          amount: -999,
          cleared: :cleared,
          source: :file
        })

      %{waiting: waiting, uncategorised: uncategorised}
    end

    test "the waiting chip counts what waits and the rows are marked", c do
      {:ok, view, _html} = live(c.conn, ~p"/budget/accounts/#{c.giro}")

      assert has_element?(view, "#approve-all", "Alle bestätigen")
      assert has_element?(view, ~s|#approve-all[aria-label="Alle 2 bestätigen"]|)
      assert has_element?(view, "#approve-all-count", "2")
      refute has_element?(view, "#show-unapproved")
      refute render(view) =~ "Ansehen"
      assert has_element?(view, "tr#tx-#{c.waiting.id}.app-unapproved")
      refute has_element?(view, "tr#tx-#{c.shopping.id}.app-unapproved")
      assert has_element?(view, "#tx-#{c.uncategorised.id}", "Nicht kategorisiert")

      assert has_element?(
               view,
               sidebar_link("/budget/accounts/#{c.giro.id}") <>
                 ~s([aria-label*="2 zu bestätigen"])
             )

      view |> element("#view-menu a", "Zu bestätigen") |> render_click()
      assert_patch(view, ~p"/budget/accounts/#{c.giro}?filter=unapproved")
    end

    test "approves one on the desktop", c do
      {:ok, view, _html} = live(c.conn, ~p"/budget/accounts/#{c.giro}")

      view |> element("#tx-#{c.waiting.id}-approve") |> render_click()

      assert reload(c.waiting).approved
      assert has_element?(view, "#approve-all-count", "1")
      refute has_element?(view, "#tx-#{c.waiting.id}-approve")
    end

    test "approves one on the phone", c do
      {:ok, view, _html} = live(c.conn, ~p"/budget/accounts/#{c.giro}")

      assert has_element?(view, "#tx-card-#{c.waiting.id}.app-unapproved-item")
      view |> element("#tx-card-#{c.waiting.id}-approve") |> render_click()

      assert reload(c.waiting).approved
      refute has_element?(view, "#tx-card-#{c.waiting.id}.app-unapproved-item")
    end

    test "approves all, match proposals stay open", c do
      {:ok, proposal} =
        Ledger.create_transaction(budget_scope(), %{
          account_id: c.giro.id,
          date: ~D[2026-10-04],
          amount: -8_743,
          cleared: :cleared,
          source: :bank,
          matched_transaction_id: c.shopping.id
        })

      elsewhere =
        transaction_fixture(account_id: c.savings.id, approved: false, source: :api)

      {:ok, view, _html} = live(c.conn, ~p"/budget/accounts/#{c.giro}")
      view |> element("#approve-all") |> render_click()

      assert reload(c.waiting).approved and reload(c.uncategorised).approved
      refute reload(proposal).approved
      assert reload(proposal).matched_transaction_id == c.shopping.id
      refute reload(elsewhere).approved
      refute has_element?(view, "#approve-all")
      refute has_element?(view, "#approve-all-item")
      assert has_element?(view, "#accept-all-matches")

      assert has_element?(
               view,
               "#flash-info",
               "2 bestätigt. 1 Zuordnungsvorschlag bleibt offen: Zuordnen oder Trennen."
             )

      {:ok, view, _html} = live(c.conn, ~p"/budget/accounts/all")
      assert has_element?(view, "#approve-all-count", "1")
      view |> element("#approve-all") |> render_click()
      assert reload(elsewhere).approved
    end

    test "approve all asks first when a reconciled transaction waits", c do
      {:ok, _old} =
        Ledger.update_transaction(budget_scope(), c.old, %{approved: false},
          reconciled: :confirmed
        )

      {:ok, view, _html} = live(c.conn, ~p"/budget/accounts/#{c.giro}")

      assert asked(view, "#approve-all").label == "Ändern"

      confirm_click(
        view,
        "#approve-all",
        "Eine abgeglichene Buchung ist dabei. Trotzdem ändern?"
      )

      assert reload(c.old).approved
    end

    test "approves and categorises the selected ones", c do
      {:ok, view, _html} = live(c.conn, ~p"/budget/accounts/#{c.giro}")
      refute bulk?(view)

      view |> element("#tx-#{c.waiting.id}-select") |> render_click()
      view |> element("#tx-#{c.uncategorised.id}-select") |> render_click()
      view |> element("#tx-#{c.transfer.id}-select") |> render_click()
      assert has_element?(view, "#bulk", "3 Buchungen")
      assert has_element?(view, "tbody#tx-#{c.waiting.id}-rows.is-selected")

      # The category picker puts the pick into the form and submits it.
      view
      |> form("#categorise-form")
      |> render_submit(%{category_id: c.groceries.id})

      assert reload(c.uncategorised).category_id == c.groceries.id
      # A transfer between budget accounts takes no category.
      assert reload(c.transfer).category_id == nil
      assert has_element?(view, "#flash-info", "2 kategorisiert")

      view |> element("#approve-selected") |> render_click()
      assert reload(c.waiting).approved and reload(c.uncategorised).approved
      refute bulk?(view)
    end

    test "approving the selected ones keeps the selection when nothing is approved", c do
      {:ok, _old} =
        Ledger.update_transaction(budget_scope(), c.old, %{approved: false},
          reconciled: :confirmed
        )

      {:ok, view, _html} = live(c.conn, ~p"/budget/accounts/#{c.giro}")

      view |> element("#tx-#{c.shopping.id}-select") |> render_click()
      # As in YNAB the bar offers approving only when one of them waits.
      refute has_element?(view, "#approve-selected")
      render_click(view, "approve_selected", %{})
      refute has_element?(view, "#flash-info", "0 bestätigt")
      assert has_element?(view, "#flash-info", "Keine der ausgewählten Buchungen wartet")
      assert has_element?(view, "#bulk", "1 Buchung")

      view |> element("#tx-#{c.waiting.id}-select") |> render_click()
      view |> element("#tx-#{c.old.id}-select") |> render_click()
      # Without the confirmation the reconciled one stays locked, and so do the others.
      render_click(view, "approve_selected", %{})
      assert has_element?(view, "#flash-error", "Nicht geändert: Buchung ist abgeglichen")
      refute reload(c.waiting).approved
      assert has_element?(view, "#bulk", "3 Buchungen")
    end

    test "selecting all takes the shown rows, and the selection can be cleared", c do
      {:ok, view, _html} = live(c.conn, ~p"/budget/accounts/#{c.giro}?filter=unapproved")

      view |> element("#select-all") |> render_click()
      assert has_element?(view, "#bulk", "2 Buchungen")

      view |> element(~s|#bulk button[aria-label="Auswahl aufheben"]|) |> render_click()
      refute bulk?(view)
    end

    test "categorising selected reconciled transactions asks first", c do
      {:ok, view, _html} = live(c.conn, ~p"/budget/accounts/#{c.giro}")

      view |> element("#tx-#{c.old.id}-select") |> render_click()
      # It is approved already, so approving it changes nothing.
      refute has_element?(view, "#approve-selected")

      confirm_click(
        view,
        "#categorise-submit",
        "Diese Buchung ist abgeglichen. Trotzdem ändern?",
        with: %{category_id: Categories.ready_to_assign!(budget_scope()).id}
      )

      assert reload(c.old).category_id == Categories.ready_to_assign!(budget_scope()).id
    end
  end

  describe "match proposals" do
    setup c do
      {:ok, proposal} =
        Ledger.create_transaction(budget_scope(), %{
          account_id: c.giro.id,
          date: ~D[2026-10-04],
          amount: -8_743,
          payee_name: "FRISCHMARKT FILIALE 12",
          memo: "Kartenzahlung",
          cleared: :cleared,
          source: :file,
          matched_transaction_id: c.shopping.id
        })

      {:ok, _origin} = Ledger.add_origin(budget_scope(), proposal, :file, "MM-0001")
      %{proposal: proposal}
    end

    test "show beside the register with what they match, counting nowhere", c do
      {:ok, view, _html} = live(c.conn, ~p"/budget/accounts/#{c.giro}")
      id = c.proposal.id

      assert has_element?(view, "tr#proposal-#{id}.app-unapproved", "FRISCHMARKT FILIALE 12")
      assert has_element?(view, "#proposal-#{id}", "87,43")

      assert has_element?(
               view,
               "#proposal-#{id}-match",
               "passt zu Buchung vom 02.10.2026 · Frischmarkt"
             )

      assert has_element?(view, "#proposal-#{id}-accept", "Zuordnen")
      assert has_element?(view, "#proposal-#{id}-reject", "Trennen")
      assert has_element?(view, "#proposal-card-#{id}", "passt zu Buchung vom 02.10.2026")
      assert has_element?(view, "#proposal-card-#{id}-accept")
      refute has_element?(view, "#proposal-#{id}-select")

      assert has_element?(view, "#approve-all-count", "1")
      assert has_element?(view, "#accept-all-matches", "Alle zuordnen")
      assert has_element?(view, "#accept-all-matches-item", "Alle zuordnen")

      assert has_element?(
               view,
               sidebar_link("/budget/accounts/#{c.giro.id}") <>
                 ~s([aria-label*="2 zu bestätigen"])
             )

      assert has_element?(view, "#balance-working", "2.598,71")

      {:ok, view, _html} = live(c.conn, ~p"/budget/accounts/all")
      assert has_element?(view, "#proposal-#{id}")
    end

    test "follow the view and the search", c do
      id = c.proposal.id

      {:ok, view, _html} = live(c.conn, ~p"/budget/accounts/#{c.giro}?filter=unapproved")
      assert has_element?(view, "#proposal-#{id}")

      {:ok, view, _html} = live(c.conn, ~p"/budget/accounts/#{c.giro}?filter=uncleared")
      refute has_element?(view, "#proposal-#{id}")

      {:ok, view, _html} = live(c.conn, ~p"/budget/accounts/#{c.giro}?q=filiale")
      assert has_element?(view, "#proposal-#{id}")
      refute has_element?(view, "#tx-#{c.shopping.id}")

      {:ok, view, _html} = live(c.conn, ~p"/budget/accounts/#{c.giro}?q=gehalt")
      refute has_element?(view, "#proposal-#{id}")
    end

    test "Zuordnen merges the import into the existing transaction", c do
      {:ok, view, _html} = live(c.conn, ~p"/budget/accounts/#{c.giro}")

      view |> element("#proposal-#{c.proposal.id}-accept") |> render_click()

      assert %Transaction{date: ~D[2026-10-04], cleared: :cleared, approved: true} =
               reload(c.shopping)

      assert Repo.get(Transaction, c.proposal.id) == nil
      assert has_element?(view, "#flash-info", "Zugeordnet.")
      refute has_element?(view, "#proposal-#{c.proposal.id}")
      assert has_element?(view, "#approve-all-count", "1")
      refute has_element?(view, "#accept-all-matches")
    end

    test "Trennen keeps the import as a transaction of its own", c do
      {:ok, view, _html} = live(c.conn, ~p"/budget/accounts/#{c.giro}")

      view |> element("#proposal-card-#{c.proposal.id}-reject") |> render_click()

      assert %Transaction{matched_transaction_id: nil, approved: true} = reload(c.proposal)
      assert has_element?(view, "#flash-info", "Getrennt und als eigene Buchung bestätigt.")
      assert has_element?(view, "#tx-#{c.proposal.id}")
      refute has_element?(view, "#proposal-#{c.proposal.id}")
    end

    test "Alle zuordnen accepts every open proposal", c do
      {:ok, other} =
        Ledger.create_transaction(budget_scope(), %{
          account_id: c.giro.id,
          date: ~D[2026-10-02],
          amount: 324_000,
          cleared: :cleared,
          source: :file,
          matched_transaction_id: c.salary.id
        })

      {:ok, view, _html} = live(c.conn, ~p"/budget/accounts/#{c.giro}")
      assert has_element?(view, "#approve-all-count", "1")

      view |> element("#accept-all-matches") |> render_click()

      assert Ledger.list_match_proposals(budget_scope(), c.giro) == []
      assert reload(c.salary).date == ~D[2026-10-02]
      assert Repo.get(Transaction, other.id) == nil
      assert has_element?(view, "#flash-info", "2 zugeordnet.")
      refute has_element?(view, "#accept-all-matches")
    end

    test "a refused Zuordnen says why and keeps the proposal", c do
      {:ok, view, _html} = live(c.conn, ~p"/budget/accounts/#{c.giro}")

      Repo.update_all(from(t in Transaction, where: t.id == ^c.shopping.id),
        set: [cleared: :reconciled]
      )

      view |> element("#proposal-#{c.proposal.id}-accept") |> render_click()

      assert has_element?(
               view,
               "#flash-error",
               "Nicht geändert: Zugeordnete Buchung ist abgeglichen"
             )

      assert reload(c.proposal).matched_transaction_id == c.shopping.id
    end

    test "a proposal decided in another tab says so", c do
      id = c.proposal.id
      buttons = ["#proposal-#{id}-accept", "#proposal-card-#{id}-reject", "#accept-all-matches"]

      views =
        Enum.map(buttons, fn _button -> elem(live(c.conn, ~p"/budget/accounts/#{c.giro}"), 1) end)

      {:ok, _} = Ledger.accept_match(budget_scope(), c.proposal)

      for {view, button} <- Enum.zip(views, buttons) do
        view |> element(button) |> render_click()

        assert has_element?(
                 view,
                 "#flash-error",
                 "Nicht geändert: Der Zuordnungsvorschlag ist schon entschieden."
               )

        refute has_element?(view, "#proposal-#{id}")
      end
    end

    test "Zuordnen asks first when it moves a reconciled counterpart", c do
      counterpart_id = reload(c.transfer).transfer_transaction_id

      Repo.update_all(from(t in Transaction, where: t.id == ^counterpart_id),
        set: [cleared: :reconciled]
      )

      {:ok, proposal} =
        Ledger.create_transaction(budget_scope(), %{
          account_id: c.giro.id,
          date: ~D[2026-10-05],
          amount: -20_000,
          cleared: :cleared,
          source: :file,
          matched_transaction_id: c.transfer.id
        })

      {:ok, view, _html} = live(c.conn, ~p"/budget/accounts/#{c.giro}")

      refute has_element?(view, "#proposal-#{c.proposal.id}-accept[aria-haspopup]")
      assert asked(view, "#accept-all-matches").label == "Zuordnen"
      assert asked(view, "#proposal-card-#{proposal.id}-accept").label == "Zuordnen"
      assert asked(view, "#proposal-#{proposal.id}-accept").text =~ "Datum aus dem Import"

      confirm_click(
        view,
        "#proposal-#{proposal.id}-accept",
        "Eine Gegenbuchung ist abgeglichen. Trotzdem zuordnen?"
      )

      assert Repo.get!(Transaction, counterpart_id).date == ~D[2026-10-05]
    end
  end

  defp bulk?(view), do: has_element?(view, "#bulk-status", "Buchung")
end
