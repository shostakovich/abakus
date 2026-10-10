defmodule AbakusWeb.TransactionEditorTest do
  use AbakusWeb.ConnCase

  import Phoenix.LiveViewTest
  import Abakus.DomainFixtures

  alias Abakus.{Categories, Ledger, Repo}
  alias Abakus.Ledger.{Subtransaction, Transaction}

  setup :register_and_log_in_user

  setup %{conn: conn} do
    giro = account_fixture(name: "💶 Girokonto", kind: :checking)
    savings = account_fixture(name: "🏦 Sparkonto", kind: :savings)
    depot = account_fixture(name: "📈 Depot", kind: :tracking)
    groceries = category_fixture(name: "🛒 Lebensmittel")
    saving = category_fixture(name: "💰 Sparen")
    market = payee_fixture(name: "Frischmarkt", last_category_id: groceries.id)

    %{
      conn: put_connect_params(conn, %{"today" => "2026-10-09"}),
      giro: giro,
      savings: savings,
      depot: depot,
      groceries: groceries,
      saving: saving,
      market: market
    }
  end

  defp reload(%{id: id}), do: Repo.get!(Transaction, id)

  defp newest(account) do
    account |> Ledger.list_transactions() |> List.first() |> then(&Ledger.get_transaction!(&1.id))
  end

  defp open_new(c, account) do
    {:ok, view, _html} = live(c.conn, ~p"/accounts/#{account}")
    view |> element("#new-transaction") |> render_click()
    assert has_element?(view, "tbody#tx-editor")
    view
  end

  # A click selects the row, the next one into a cell opens it there.
  defp open_edit(view, transaction, cell \\ "td.app-payee") do
    view |> element("#tx-#{transaction.id} #{cell}") |> render_click()
    view |> element("#tx-#{transaction.id} #{cell}") |> render_click()
    assert has_element?(view, "#tx-editor")
    view
  end

  defp pick(view, side, field, value) do
    view
    |> with_target("#tx-editor")
    |> render_hook("pick", %{"side" => side, "field" => field, "value" => value})
  end

  defp change(view, changed, target) do
    view
    |> element("#tx-form")
    |> render_change(Map.put(%{"transaction" => changed}, "_target", ["transaction" | target]))
  end

  defp submit(view, params \\ %{}) do
    view |> form("#tx-form", transaction: params) |> render_submit()
  end

  defp category(view, id), do: has_element?(view, ~s|#tx-category-combo[data-value="#{id}"]|)

  describe "creating" do
    test "Buchung adds an empty row on top, today, and books an outflow in the register's account",
         c do
      view = open_new(c, c.giro)

      assert has_element?(view, ~s|#tx-editor[data-focus="tx-date"]|)
      assert has_element?(view, ~s|#tx-date[value="2026-10-09"]|)
      refute has_element?(view, "#tx-account")
      assert has_element?(view, "#tx-save", "Speichern")
      refute has_element?(view, "#tx-delete")

      pick(view, "main", "payee", "p:🥖 Bäckerei")
      pick(view, "main", "category", "#{c.groceries.id}")
      submit(view, %{outflow: "12,34", memo: "Brötchen"})

      refute has_element?(view, "#tx-editor")
      assert has_element?(view, "#flash-info", "Gebucht")

      transaction = newest(c.giro)

      assert %Transaction{amount: -1_234, date: ~D[2026-10-09], memo: "Brötchen", approved: true} =
               transaction

      assert transaction.payee.name == "🥖 Bäckerei"
      assert transaction.category_id == c.groceries.id
      assert has_element?(view, "#tx-#{transaction.id}", "Bäckerei")
      assert has_element?(view, "#balance-working", "−12,34 €")
    end

    test "typing one of outflow and inflow clears the other; income goes to Ready to Assign", c do
      view = open_new(c, c.giro)
      rta = Categories.ready_to_assign!().id

      change(view, %{"outflow" => "5"}, ["outflow"])
      change(view, %{"outflow" => "5", "inflow" => "100"}, ["inflow"])
      assert has_element?(view, ~s|#tx-outflow[value=""]|)
      assert category(view, rta)

      change(view, %{"outflow" => "5", "inflow" => "100"}, ["outflow"])
      assert has_element?(view, ~s|#tx-inflow[value=""]|)
      refute category(view, rta)

      change(view, %{"outflow" => "", "inflow" => "100"}, ["inflow"])
      submit(view)
      assert %Transaction{amount: 10_000, category_id: ^rta} = newest(c.giro)
    end

    test "a payee suggests its last category, which goes when the payee changes", c do
      view = open_new(c, c.giro)
      assert render(view) =~ ~s|data-value="p:Frischmarkt"|

      pick(view, "main", "payee", "p:Frischmarkt")
      assert category(view, c.groceries.id)
      assert has_element?(view, ~s|#tx-category[value$="🛒 Lebensmittel"]|)

      # Typed instead of picked, on leaving the field.
      change(view, %{"payee" => "Unbekannt"}, ["payee"])
      assert category(view, "")

      change(view, %{"payee" => "frischmarkt"}, ["payee"])
      assert category(view, c.groceries.id)

      pick(view, "main", "category", "#{c.saving.id}")
      pick(view, "main", "payee", "p:Noch einer")
      assert category(view, c.saving.id)
    end

    test "a payee whose last category was hidden in YNAB suggests it", c do
      gym = category_fixture(name: "🏋️ Fitness", hidden: true)
      payee_fixture(name: "Studio", last_category_id: gym.id)
      view = open_new(c, c.giro)

      pick(view, "main", "payee", "p:Studio")
      assert category(view, gym.id)
    end

    test "the category picker lists Ready to Assign and the categories with what they have", c do
      {:ok, _} = Categories.assign(c.groceries, ~D[2026-10-01], 30_000)
      view = open_new(c, c.giro)
      html = render(view)

      assert html =~ "Zu verteilen"
      assert html =~ ~r|data-value="#{c.groceries.id}".*?300,00|s
      assert html =~ "Aufteilen"
    end

    test "Escape and Abbrechen leave without booking", c do
      view = open_new(c, c.giro)
      view |> element("#tx-editor") |> render_keydown(%{"key" => "Escape"})
      refute has_element?(view, "#tx-editor")

      view |> element("#new-transaction") |> render_click()
      view |> element("#tx-cancel") |> render_click()
      refute has_element?(view, "#tx-editor")
      assert Ledger.list_transactions(c.giro) == []
    end

    test "the phone opens a sheet, amount first, whose sign makes an inflow", c do
      {:ok, view, _html} = live(c.conn, ~p"/accounts/#{c.giro}")

      view |> element("#new-transaction-fab") |> render_click()
      assert has_element?(view, "#tx-editor .app-sheet #tx-amount[name='transaction[outflow]']")
      refute has_element?(view, "tbody#tx-editor")

      view |> element("#tx-sign") |> render_click()
      assert has_element?(view, "#tx-amount[name='transaction[inflow]']")

      submit(view, %{inflow: "100"})
      assert %Transaction{amount: 10_000} = newest(c.giro)
    end

    test "from all accounts it books in the first budget account, or the one picked", c do
      {:ok, view, _html} = live(c.conn, ~p"/accounts/all")
      view |> element("#new-transaction") |> render_click()

      assert has_element?(view, ~s|#tx-account option[selected][value="#{c.giro.id}"]|)
      submit(view, %{outflow: "5", account_id: c.savings.id})
      assert %Transaction{amount: -500} = newest(c.savings)
    end

    test "fed and closed accounts take no manual entry", c do
      shared = account_fixture(name: "👫 Geteilt", fed_by: :shared_expenses)
      closed = account_fixture(name: "Alt", closed: true)

      for account <- [shared, closed] do
        {:ok, view, _html} = live(c.conn, ~p"/accounts/#{account}")
        refute has_element?(view, "#new-transaction")
        refute has_element?(view, "#new-transaction-fab")
        render_click(view, "new", %{"layout" => "row"})
        refute has_element?(view, "#tx-editor")
      end

      {:ok, view, _html} = live(c.conn, ~p"/accounts/#{c.depot}")
      assert has_element?(view, "#new-transaction")

      {:ok, view, _html} = live(c.conn, ~p"/accounts/all")
      view |> element("#new-transaction") |> render_click()
      refute has_element?(view, ~s|#tx-account option[value="#{shared.id}"]|)
      refute has_element?(view, ~s|#tx-account option[value="#{closed.id}"]|)
      assert has_element?(view, ~s|#tx-account option[value="#{c.depot.id}"]|)

      # Transfers may go to a fed account, not to a closed one.
      html = render(view)
      assert html =~ ~s|data-value="a:#{shared.id}"|
      refute html =~ ~s|data-value="a:#{closed.id}"|
    end

    test "shows what the Ledger refuses and keeps the row", c do
      view = open_new(c, c.giro)

      submit(view, %{outflow: "12,345"})
      assert has_element?(view, "#tx-error", "Betrag ist ungültig")

      view |> with_target("#tx-editor") |> render_click("split", %{})
      submit(view, %{outflow: "1", subtransactions: %{"0" => %{outflow: "1"}}})
      assert has_element?(view, "#tx-error", "mindestens zwei Teile")

      submit(view, %{
        outflow: "1",
        subtransactions: %{"0" => %{outflow: "60"}, "1" => %{outflow: "30"}}
      })

      assert has_element?(view, "#tx-error", "Betrag muss der Summe der Teile entsprechen")
      assert has_element?(view, "#tx-editor")
    end
  end

  describe "transfers" do
    test "are picked as payees; between budget accounts they have no category", c do
      view = open_new(c, c.giro)
      html = render(view)

      assert html =~ ~s|data-value="a:#{c.savings.id}"|
      refute html =~ ~s|data-value="a:#{c.giro.id}"|

      pick(view, "main", "payee", "a:#{c.savings.id}")
      assert has_element?(view, ~s|#tx-payee[value="↔ 🏦 Sparkonto"]|)
      assert has_element?(view, "#tx-category[readonly]")

      submit(view, %{outflow: "200", memo: "Rücklagen"})

      transfer = newest(c.giro)
      assert %Transaction{amount: -20_000, category_id: nil} = transfer
      assert transfer.payee_id == c.savings.transfer_payee.id

      assert %Transaction{amount: 20_000, memo: "Rücklagen", category_id: nil} =
               reload(transfer.transfer_transaction)

      assert has_element?(view, "#tx-#{transfer.id}", "↔ 🏦 Sparkonto")
    end

    test "between a budget and a tracking account take a category, the last one used first", c do
      view = open_new(c, c.giro)

      pick(view, "main", "payee", "a:#{c.depot.id}")
      assert has_element?(view, "#tx-category-combo")
      assert category(view, "")

      pick(view, "main", "category", "#{c.saving.id}")
      submit(view, %{outflow: "500"})

      transfer = newest(c.giro)
      assert transfer.category_id == c.saving.id

      assert %Transaction{amount: 50_000, category_id: nil} =
               reload(transfer.transfer_transaction)

      view |> element("#new-transaction") |> render_click()
      pick(view, "main", "payee", "a:#{c.depot.id}")
      assert category(view, c.saving.id)
    end

    test "from a tracking account put the category on the counterpart, and need it", c do
      view = open_new(c, c.depot)
      refute has_element?(view, "#register-table th", "Kategorie")
      refute has_element?(view, "#tx-category")

      pick(view, "main", "payee", "a:#{c.giro.id}")
      assert has_element?(view, "td.app-payee #tx-category-combo")

      submit(view, %{inflow: "80"})

      assert has_element?(
               view,
               "#tx-error",
               "Kategorie muss bei einer Umbuchung mit einem Tracking-Konto ausgefüllt werden"
             )

      pick(view, "main", "category", "#{c.saving.id}")
      submit(view, %{inflow: "80"})

      transfer = newest(c.depot)
      assert %Transaction{amount: 8_000, category_id: nil} = transfer
      assert %Transaction{amount: -8_000} = counterpart = reload(transfer.transfer_transaction)
      assert counterpart.category_id == c.saving.id
    end

    test "the transfer is edited from its other side too", c do
      {:ok, transfer} =
        Ledger.create_transaction(%{
          account_id: c.giro.id,
          date: ~D[2026-10-03],
          amount: -20_000,
          payee_id: c.savings.transfer_payee.id
        })

      {:ok, view, _html} = live(c.conn, ~p"/accounts/#{c.savings}")
      open_edit(view, %{id: transfer.transfer_transaction_id})

      assert has_element?(view, ~s|#tx-payee[value="↔ 💶 Girokonto"]|)
      assert has_element?(view, ~s|#tx-inflow[value="200,00"]|)

      submit(view, %{inflow: "250"})
      assert reload(transfer).amount == -25_000
    end

    test "typing over a transfer makes it a payee again", c do
      view = open_new(c, c.giro)

      pick(view, "main", "payee", "a:#{c.savings.id}")
      change(view, %{"payee" => "↔ 🏦 Sparkonto"}, ["payee"])
      assert has_element?(view, ~s|#tx-payee[value="↔ 🏦 Sparkonto"]|)

      change(view, %{"payee" => "Sparkasse"}, ["payee"])
      submit(view, %{outflow: "3"})

      assert %{payee: %{name: "Sparkasse", transfer_account_id: nil}} = newest(c.giro)
    end
  end

  describe "splits" do
    test "Aufteilen gives parts with payees, categories and transfers of their own", c do
      view = open_new(c, c.giro)

      pick(view, "main", "payee", "p:Frischmarkt")
      view |> with_target("#tx-editor") |> render_click("split", %{})
      view |> element("#tx-add-sub") |> render_click()
      assert has_element?(view, "#tx-category", "Aufgeteilt")

      pick(view, "0", "category", "#{c.groceries.id}")
      pick(view, "1", "payee", "a:#{c.savings.id}")
      pick(view, "2", "payee", "a:#{c.depot.id}")

      change(
        view,
        %{
          "outflow" => "100",
          "subtransactions" => %{
            "0" => %{"outflow" => "60", "memo" => "Obst"},
            "1" => %{"outflow" => "30"},
            "2" => %{"outflow" => "5"}
          }
        },
        ["subtransactions", "2", "outflow"]
      )

      assert has_element?(view, "#tx-remainder-out", "5,00")
      assert has_element?(view, "#tx-sub-1-category[readonly]")
      assert has_element?(view, "#tx-sub-2-category-combo")

      pick(view, "2", "category", "#{c.saving.id}")

      submit(view, %{
        outflow: "100",
        subtransactions: %{"2" => %{outflow: "10"}}
      })

      split = newest(c.giro)
      assert %Transaction{amount: -10_000, category_id: nil, payee_id: market_id} = split
      assert market_id == c.market.id

      assert [groceries, savings, depot] = split.subtransactions
      assert %Subtransaction{amount: -6_000, memo: "Obst"} = groceries
      assert groceries.category_id == c.groceries.id
      assert %Subtransaction{amount: -3_000, category_id: nil} = savings
      assert %Transaction{amount: 3_000, account_id: savings_id} = savings.transfer_transaction
      assert savings_id == c.savings.id
      assert depot.category_id == c.saving.id
      assert %Transaction{amount: 1_000, category_id: nil} = depot.transfer_transaction

      assert has_element?(view, "#tx-#{split.id}", "Aufgeteilt (3)")
      assert has_element?(view, "#tx-#{split.id}-part-1", "↔ 🏦 Sparkonto")
      assert has_element?(view, "#tx-#{split.id}-part-0", "Lebensmittel")
      assert has_element?(view, "#tx-#{split.id}-parts")
    end

    test "parts imported from YNAB show their payees and memos and keep them", c do
      rewe = payee_fixture(name: "Rewe")
      dm = payee_fixture(name: "dm")

      split =
        transaction_fixture(
          account_id: c.giro.id,
          amount: -5_000,
          payee_id: c.market.id,
          source: :ynab,
          subtransactions: [
            %{amount: -3_000, payee_id: rewe.id, memo: "Obst", category_id: c.groceries.id},
            %{amount: -2_000, payee_id: dm.id, memo: "Seife", category_id: c.groceries.id}
          ]
        )

      {:ok, view, _html} = live(c.conn, ~p"/accounts/#{c.giro}")
      open_edit(view, split)

      assert has_element?(view, ~s|#tx-sub-0-payee[value="Rewe"]|)
      assert has_element?(view, ~s|#tx-sub-0-memo[value="Obst"]|)
      [first, second] = Ledger.get_transaction!(split.id).subtransactions

      pick(view, "1", "category", "#{c.saving.id}")
      submit(view)

      assert [obst, seife] = Ledger.get_transaction!(split.id).subtransactions
      assert {obst.id, obst.payee_id, obst.memo} == {first.id, rewe.id, "Obst"}

      assert {seife.id, seife.payee_id, seife.memo, seife.category_id} ==
               {second.id, dm.id, "Seife", c.saving.id}
    end

    test "shows the Ledger's errors on the split as a whole", c do
      split =
        transaction_fixture(
          account_id: c.giro.id,
          amount: -5_000,
          subtransactions: [
            %{amount: -3_000, category_id: c.groceries.id},
            %{amount: -2_000, category_id: c.saving.id}
          ]
        )

      {:ok, view, _html} = live(c.conn, ~p"/accounts/all")
      open_edit(view, split)
      submit(view, %{account_id: c.depot.id})

      assert has_element?(view, "#tx-error", "Aufteilung: muss in einem Tracking-Konto leer sein")
      assert reload(split).account_id == c.giro.id
    end

    test "a split's transfer counterpart opens the split", c do
      split =
        transaction_fixture(
          account_id: c.giro.id,
          amount: -5_000,
          subtransactions: [
            %{amount: -3_000, category_id: c.groceries.id},
            %{amount: -2_000, payee_id: c.savings.transfer_payee.id}
          ]
        )

      counterpart =
        Enum.at(Ledger.get_transaction!(split.id).subtransactions, 1).transfer_transaction_id

      {:ok, view, _html} = live(c.conn, ~p"/accounts/#{c.savings}")
      open_edit(view, %{id: counterpart})

      assert has_element?(view, "#tx-split-of", "💶 Girokonto")
      assert has_element?(view, "#tx-sub-1")

      submit(view, %{memo: "Geändert"})
      assert reload(split).memo == "Geändert"
    end

    test "removing one of the last two parts ends the split", c do
      view = open_new(c, c.giro)

      view |> with_target("#tx-editor") |> render_click("split", %{})
      pick(view, "1", "category", "#{c.saving.id}")
      view |> element("#tx-sub-0-remove") |> render_click()

      refute has_element?(view, "#tx-sub-1")
      assert category(view, c.saving.id)
    end
  end

  describe "editing" do
    setup c do
      %{
        shopping:
          transaction_fixture(
            account_id: c.giro.id,
            date: ~D[2026-10-02],
            amount: -8_743,
            payee_id: c.market.id,
            category_id: c.groceries.id,
            approved: false
          )
      }
    end

    test "a click selects the row, a click into a cell opens it there; saving approves", c do
      {:ok, view, _html} = live(c.conn, ~p"/accounts/#{c.giro}?filter=unapproved")

      view |> element("#tx-#{c.shopping.id} td.app-out") |> render_click()
      assert has_element?(view, "tr#tx-#{c.shopping.id}.table-active")
      refute has_element?(view, "#tx-editor")

      view |> element("#tx-#{c.shopping.id} td.app-out") |> render_click()
      assert has_element?(view, ~s|#tx-editor[data-focus="tx-outflow"]|)
      assert has_element?(view, ~s|#tx-outflow[value="87,43"]|)
      assert has_element?(view, ~s|#tx-payee[value="Frischmarkt"]|)
      assert has_element?(view, "#tx-save", "Bestätigen")
      refute has_element?(view, "#bulk")

      submit(view, %{outflow: "90", date: "2026-10-03"})

      assert %Transaction{amount: -9_000, date: ~D[2026-10-03], approved: true} =
               reload(c.shopping)

      assert has_element?(view, "#flash-info", "Gespeichert")
      refute has_element?(view, "#tx-editor")
    end

    test "only one row is edited at a time", c do
      other = transaction_fixture(account_id: c.giro.id, amount: -100)
      {:ok, view, _html} = live(c.conn, ~p"/accounts/#{c.giro}")
      open_edit(view, c.shopping)

      render_click(view, "row_click", %{"id" => "#{other.id}", "field" => "memo"})
      render_click(view, "row_click", %{"id" => "#{other.id}", "field" => "memo"})
      assert has_element?(view, ~s|#tx-payee[value="Frischmarkt"]|)
      assert has_element?(view, "tr#tx-#{other.id}")
    end

    test "a search that hides the edited row ends the edit", c do
      {:ok, view, _html} = live(c.conn, ~p"/accounts/#{c.giro}")
      open_edit(view, c.shopping)

      view |> form("#register-search", q: "nichts davon") |> render_change()
      refute has_element?(view, "#tx-editor")

      view |> form("#register-search", q: "") |> render_change()
      open_edit(view, c.shopping)
    end

    test "the phone opens the card in a sheet", c do
      {:ok, view, _html} = live(c.conn, ~p"/accounts/#{c.giro}")
      view |> element("#tx-card-#{c.shopping.id}-edit") |> render_click()

      assert has_element?(view, "#tx-editor .app-sheet")
      assert has_element?(view, ~s|#tx-amount[value="87,43"]|)
      assert has_element?(view, "#tx-delete[data-confirm]")
    end

    test "deletes from the selection bar after asking", c do
      {:ok, view, _html} = live(c.conn, ~p"/accounts/#{c.giro}")

      view |> element("#tx-#{c.shopping.id}-select") |> render_click()
      assert has_element?(view, ~s|#delete-selected[data-confirm="Buchung löschen?"]|)
      view |> element("#delete-selected") |> render_click()

      assert reload(c.shopping).deleted_at
      refute has_element?(view, "#tx-#{c.shopping.id}")
      refute has_element?(view, "#bulk")
      assert has_element?(view, "#flash-info", "gelöscht")
    end

    test "deleting a split's counterpart deletes the split, once", c do
      split =
        transaction_fixture(
          account_id: c.giro.id,
          amount: -5_000,
          subtransactions: [
            %{amount: -3_000, category_id: c.groceries.id},
            %{amount: -2_000, payee_id: c.savings.transfer_payee.id}
          ]
        )

      counterpart =
        Enum.at(Ledger.get_transaction!(split.id).subtransactions, 1).transfer_transaction_id

      {:ok, view, _html} = live(c.conn, ~p"/accounts/all")
      view |> element("#tx-#{split.id}-select") |> render_click()
      view |> element("#tx-#{counterpart}-select") |> render_click()
      assert has_element?(view, ~s|#delete-selected[data-confirm="2 Buchungen löschen?"]|)
      view |> element("#delete-selected") |> render_click()

      assert reload(split).deleted_at
      assert reload(%{id: counterpart}).deleted_at
      assert has_element?(view, "#flash-info", "Buchung gelöscht")
    end

    test "a reconciled transaction asks before it is changed or deleted", c do
      {:ok, old} = Ledger.update_transaction(c.shopping, %{cleared: :reconciled})
      {:ok, view, _html} = live(c.conn, ~p"/accounts/#{c.giro}")

      open_edit(view, old)
      assert has_element?(view, "#tx-save[data-confirm]")
      submit(view, %{memo: "Nachgetragen"})
      assert %Transaction{memo: "Nachgetragen", cleared: :reconciled} = reload(old)

      view |> element("#tx-#{old.id}-select") |> render_click()
      view |> element("#tx-#{old.id}-select") |> render_click()
      assert has_element?(view, ~s|#delete-selected[data-confirm*="abgeschlossen"]|)
      view |> element("#delete-selected") |> render_click()
      assert reload(old).deleted_at
    end

    test "a counterpart that is reconciled asks before deleting too", c do
      {:ok, transfer} =
        Ledger.create_transaction(%{
          account_id: c.giro.id,
          date: ~D[2026-10-03],
          amount: -2_000,
          payee_id: c.savings.transfer_payee.id
        })

      {:ok, _counterpart} =
        Ledger.update_transaction(%Transaction{id: transfer.transfer_transaction_id}, %{
          cleared: :reconciled
        })

      {:ok, view, _html} = live(c.conn, ~p"/accounts/#{c.giro}")
      view |> element("#tx-#{transfer.id}-select") |> render_click()
      assert has_element?(view, ~s|#delete-selected[data-confirm*="abgeschlossen"]|)

      # Without the confirmation nothing goes.
      render_click(view, "delete_selected", %{})
      assert has_element?(view, "#flash-error", "Nicht gelöscht")
      refute reload(transfer).deleted_at
    end

    test "a deleted transaction is not found", c do
      {:ok, view, _html} = live(c.conn, ~p"/accounts/#{c.giro}")
      {:ok, _deleted} = Ledger.delete_transaction(c.shopping)

      render_click(view, "edit", %{"id" => "#{c.shopping.id}"})
      refute has_element?(view, "#tx-editor")
      assert has_element?(view, "#flash-error", "Buchung nicht gefunden")
      refute has_element?(view, "#tx-#{c.shopping.id}")
    end

    test "a transaction that never was is not found either", c do
      {:ok, view, _html} = live(c.conn, ~p"/accounts/#{c.giro}")

      for id <- ["#{c.shopping.id + 1_000}", "x"] do
        render_click(view, "edit", %{"id" => id})
        refute has_element?(view, "#tx-editor")
        assert has_element?(view, "#flash-error", "Buchung nicht gefunden")
      end

      render_click(view, "row_click", %{"id" => "#{c.shopping.id + 1_000}", "field" => "memo"})
      refute has_element?(view, "#tx-editor")
    end
  end
end
