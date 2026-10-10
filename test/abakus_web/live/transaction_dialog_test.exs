defmodule AbakusWeb.TransactionDialogTest do
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
    assert_patch(view, ~p"/accounts/#{account}/transactions/new")
    view
  end

  defp change(view, field, value) do
    view
    |> element("#transaction-form")
    |> render_change(%{"transaction" => %{field => value}, "_target" => ["transaction", field]})
  end

  defp submit(view, params) do
    view |> form("#transaction-form", transaction: params) |> render_submit()
  end

  describe "creating" do
    test "books an outflow in the register's account, today by default", c do
      view = open_new(c, c.giro)

      assert has_element?(view, "#transaction-dialog h2", "Neue Buchung")
      assert has_element?(view, ~s|#tx-account option[selected][value="#{c.giro.id}"]|)
      assert has_element?(view, ~s|#tx-date[value="2026-10-09"]|)
      refute has_element?(view, "#tx-delete")

      submit(view, %{
        amount: "12,34",
        payee: "🥖 Bäckerei",
        category_id: c.groceries.id,
        memo: "Brötchen"
      })

      assert_patch(view, ~p"/accounts/#{c.giro}")
      refute has_element?(view, "#transaction-dialog")
      assert has_element?(view, "#flash-info", "Gebucht")

      transaction = newest(c.giro)

      assert %Transaction{amount: -1_234, date: ~D[2026-10-09], memo: "Brötchen", approved: true} =
               transaction

      assert transaction.payee.name == "🥖 Bäckerei"
      assert transaction.category_id == c.groceries.id
      assert has_element?(view, "#tx-#{transaction.id}", "Bäckerei")
      assert has_element?(view, "#balance-working", "−12,34 €")
    end

    test "the sign toggle makes it an inflow", c do
      view = open_new(c, c.giro)

      view |> element("#tx-sign") |> render_click()
      assert has_element?(view, "#tx-kind-inflow[checked]")
      # Income goes to Ready to Assign unless a category is chosen.
      assert has_element?(
               view,
               ~s|#tx-category option[selected][value="#{Categories.ready_to_assign!().id}"]|
             )

      submit(view, %{amount: "100"})
      assert %Transaction{amount: 10_000} = newest(c.giro)
    end

    test "the payee suggests its last category, which goes when the payee changes", c do
      view = open_new(c, c.giro)

      change(view, "payee", "frischmarkt")
      assert has_element?(view, ~s|#tx-category option[selected][value="#{c.groceries.id}"]|)
      assert has_element?(view, "#tx-category-hint", "Frischmarkt")
      assert has_element?(view, ~s|#tx-payees option[value="Frischmarkt"]|)

      change(view, "payee", "Unbekannt")
      refute has_element?(view, "#tx-category option[selected]")
      refute has_element?(view, "#tx-category-hint")

      change(view, "category_id", "#{c.saving.id}")
      change(view, "payee", "Noch einer")
      assert has_element?(view, ~s|#tx-category option[selected][value="#{c.saving.id}"]|)
    end

    test "a payee whose last category is hidden suggests nothing", c do
      gym = category_fixture(name: "🏋️ Fitness", hidden: true)
      payee_fixture(name: "Studio", last_category_id: gym.id)
      view = open_new(c, c.giro)

      change(view, "payee", "frischmarkt")
      change(view, "payee", "Studio")
      refute has_element?(view, "#tx-category option[selected]")
      refute has_element?(view, "#tx-category-hint")
    end

    test "the phone has a button that opens the same form", c do
      {:ok, view, _html} = live(c.conn, ~p"/accounts/#{c.giro}")

      view |> element("#new-transaction-fab") |> render_click()
      assert_patch(view, ~p"/accounts/#{c.giro}/transactions/new")
      assert has_element?(view, "#transaction-dialog .app-sheet #tx-amount")
    end

    test "from all accounts it books in the first budget account", c do
      {:ok, view, _html} = live(c.conn, ~p"/accounts/all")
      view |> element("#new-transaction") |> render_click()
      assert_patch(view, ~p"/accounts/all/transactions/new")

      assert has_element?(view, ~s|#tx-account option[selected][value="#{c.giro.id}"]|)
      submit(view, %{amount: "5", account_id: c.savings.id})
      assert_patch(view, ~p"/accounts/all")
      assert %Transaction{amount: -500} = newest(c.savings)
    end

    test "fed and closed accounts take no manual entry", c do
      shared = account_fixture(name: "👫 Geteilt", fed_by: :shared_expenses)
      closed = account_fixture(name: "Alt", closed: true)

      for account <- [shared, closed] do
        {:ok, view, _html} = live(c.conn, ~p"/accounts/#{account}")
        refute has_element?(view, "#new-transaction")
        refute has_element?(view, "#new-transaction-fab")
      end

      {:ok, view, _html} = live(c.conn, ~p"/accounts/#{c.depot}")
      assert has_element?(view, "#new-transaction")

      {:ok, view, _html} = live(c.conn, ~p"/accounts/#{c.giro}/transactions/new")
      refute has_element?(view, ~s|#tx-account option[value="#{shared.id}"]|)
      refute has_element?(view, ~s|#tx-account option[value="#{closed.id}"]|)
      assert has_element?(view, ~s|#tx-account option[value="#{c.depot.id}"]|)
      # Transfers may go to a fed account.
      change(view, "kind", "transfer")
      assert has_element?(view, ~s|#tx-other-account option[value="#{shared.id}"]|)
    end

    test "closes without booking", c do
      view = open_new(c, c.giro)

      view |> element("#tx-close") |> render_click()
      assert_patch(view, ~p"/accounts/#{c.giro}")
      assert Ledger.list_transactions(c.giro) == []
    end

    test "shows what the Ledger refuses and keeps the form", c do
      view = open_new(c, c.giro)

      submit(view, %{amount: "12,345"})
      assert has_element?(view, "#tx-error", "Betrag ist ungültig")

      change(view, "split", "true")
      submit(view, %{amount: "1"})
      assert has_element?(view, "#tx-error", "mindestens zwei Teile")

      submit(view, %{
        amount: "1",
        subtransactions: %{"0" => %{amount: "60"}, "1" => %{amount: "30"}}
      })

      assert has_element?(view, "#tx-error", "Betrag muss der Summe der Teile entsprechen")
      assert has_element?(view, "#transaction-dialog")
    end
  end

  describe "transfers" do
    test "between budget accounts have no category", c do
      view = open_new(c, c.giro)

      change(view, "kind", "transfer")
      refute has_element?(view, "#tx-payee")
      refute has_element?(view, "#tx-category")
      refute has_element?(view, ~s|#tx-other-account option[value="#{c.giro.id}"]|)

      change(view, "other_account_id", "#{c.savings.id}")
      refute has_element?(view, "#tx-category")

      submit(view, %{amount: "200", other_account_id: c.savings.id, memo: "Rücklagen"})

      transfer = newest(c.giro)
      assert %Transaction{amount: -20_000, category_id: nil} = transfer
      assert transfer.payee_id == c.savings.transfer_payee.id

      assert %Transaction{amount: 20_000, memo: "Rücklagen", category_id: nil} =
               reload(transfer.transfer_transaction)
    end

    test "between a budget and a tracking account have a category on the budget side", c do
      view = open_new(c, c.giro)

      change(view, "kind", "transfer")
      change(view, "other_account_id", "#{c.depot.id}")
      assert has_element?(view, "#tx-category")

      submit(view, %{amount: "500", other_account_id: c.depot.id, category_id: c.saving.id})

      transfer = newest(c.giro)
      assert transfer.category_id == c.saving.id

      assert %Transaction{amount: 50_000, category_id: nil} =
               reload(transfer.transfer_transaction)
    end

    test "from a tracking account put the category on the counterpart", c do
      {:ok, view, _html} = live(c.conn, ~p"/accounts/#{c.depot}/transactions/new")

      change(view, "kind", "transfer")
      view |> element("#tx-sign") |> render_click()
      change(view, "other_account_id", "#{c.giro.id}")

      submit(view, %{amount: "80", other_account_id: c.giro.id, category_id: c.saving.id})

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
      view |> element("#tx-#{transfer.transfer_transaction_id}-edit") |> render_click()

      assert has_element?(view, "#tx-kind-transfer[checked]")
      assert has_element?(view, ~s|#tx-other-account option[selected][value="#{c.giro.id}"]|)
      assert has_element?(view, "#tx-sign", "+")

      submit(view, %{amount: "250"})
      assert reload(transfer).amount == -25_000
    end
  end

  describe "splits" do
    test "each subtransaction picks a category or an account, a transfer subtransaction gets its counterpart",
         c do
      view = open_new(c, c.giro)

      change(view, "split", "true")
      view |> element("#tx-add-sub") |> render_click()

      view
      |> element("#transaction-form")
      |> render_change(%{
        "transaction" => %{
          "amount" => "100",
          "subtransactions" => %{
            "0" => %{"target" => "c:#{c.groceries.id}", "amount" => "60"},
            "1" => %{"target" => "a:#{c.savings.id}", "amount" => "30"},
            "2" => %{"target" => "a:#{c.depot.id}", "amount" => "5"}
          }
        },
        "_target" => ["transaction", "subtransactions", "2", "target"]
      })

      assert has_element?(view, "#tx-remainder", "5,00")
      refute has_element?(view, "#tx-sub-1-category")
      assert has_element?(view, "#tx-sub-2-category")
      refute has_element?(view, "#tx-category")

      submit(view, %{
        amount: "100",
        payee: "Frischmarkt",
        subtransactions: %{
          "0" => %{target: "c:#{c.groceries.id}", amount: "60"},
          "1" => %{target: "a:#{c.savings.id}", amount: "30"},
          "2" => %{target: "a:#{c.depot.id}", amount: "10", category_id: c.saving.id}
        }
      })

      split = newest(c.giro)
      assert %Transaction{amount: -10_000, category_id: nil, payee_id: market_id} = split
      assert market_id == c.market.id

      assert [groceries, savings, depot] = split.subtransactions
      assert %Subtransaction{amount: -6_000} = groceries
      assert groceries.category_id == c.groceries.id
      assert %Subtransaction{amount: -3_000, category_id: nil} = savings
      assert %Transaction{amount: 3_000, account_id: savings_id} = savings.transfer_transaction
      assert savings_id == c.savings.id
      assert depot.category_id == c.saving.id
      assert %Transaction{amount: 1_000, category_id: nil} = depot.transfer_transaction
      assert has_element?(view, "#tx-#{split.id}", "Aufgeteilt (3)")
    end

    test "subtransactions from YNAB keep their payees and memos when edited", c do
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

      {:ok, view, _html} = live(c.conn, ~p"/accounts/#{c.giro}/transactions/#{split}/edit")
      assert has_element?(view, "#tx-sub-0", "Rewe · Obst")
      [first, second] = Ledger.get_transaction!(split.id).subtransactions

      submit(view, %{
        subtransactions: %{
          "0" => %{id: first.id, target: "c:#{c.groceries.id}", amount: "30"},
          "1" => %{id: second.id, target: "c:#{c.saving.id}", amount: "20"}
        }
      })

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

      {:ok, view, _html} = live(c.conn, ~p"/accounts/#{c.giro}/transactions/#{split}/edit")
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
      view |> element("#tx-#{counterpart}-edit") |> render_click()

      assert has_element?(view, "#tx-split-of", "💶 Girokonto")
      assert has_element?(view, "#tx-sub-1")

      submit(view, %{memo: "Geändert"})
      assert reload(split).memo == "Geändert"
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

    test "opens from the row on the desktop and from the card on the phone", c do
      {:ok, view, _html} = live(c.conn, ~p"/accounts/#{c.giro}?filter=unapproved")

      view |> element("#tx-#{c.shopping.id}-edit") |> render_click()

      assert_patch(
        view,
        ~p"/accounts/#{c.giro}/transactions/#{c.shopping}/edit?filter=unapproved"
      )

      assert has_element?(view, "#transaction-dialog h2", "Buchung bearbeiten")
      assert has_element?(view, ~s|#tx-amount[value="87,43"]|)
      assert has_element?(view, ~s|#tx-payee[value="Frischmarkt"]|)

      submit(view, %{amount: "90", date: "2026-10-03"})
      assert_patch(view, ~p"/accounts/#{c.giro}?filter=unapproved")

      assert %Transaction{amount: -9_000, date: ~D[2026-10-03], approved: true} =
               reload(c.shopping)

      assert has_element?(view, "#flash-info", "Gespeichert")

      {:ok, view, _html} = live(c.conn, ~p"/accounts/#{c.giro}")
      view |> element("#tx-card-#{c.shopping.id}-edit") |> render_click()
      assert_patch(view, ~p"/accounts/#{c.giro}/transactions/#{c.shopping}/edit")
    end

    test "deletes after asking", c do
      {:ok, view, _html} = live(c.conn, ~p"/accounts/#{c.giro}/transactions/#{c.shopping}/edit")

      assert has_element?(view, "#tx-delete[data-confirm]")
      view |> element("#tx-delete") |> render_click()

      assert_patch(view, ~p"/accounts/#{c.giro}")
      assert reload(c.shopping).deleted_at
      refute has_element?(view, "#tx-#{c.shopping.id}")
      assert has_element?(view, "#flash-info", "gelöscht")
    end

    test "a reconciled transaction asks before it is changed or deleted", c do
      {:ok, old} =
        Ledger.update_transaction(c.shopping, %{cleared: :reconciled})

      {:ok, view, _html} = live(c.conn, ~p"/accounts/#{c.giro}/transactions/#{old}/edit")

      assert has_element?(view, "#tx-save[data-confirm]")
      assert has_element?(view, ~s|#tx-delete[data-confirm*="abgeschlossen"]|)

      submit(view, %{memo: "Nachgetragen"})
      assert %Transaction{memo: "Nachgetragen", cleared: :reconciled} = reload(old)

      {:ok, view, _html} = live(c.conn, ~p"/accounts/#{c.giro}/transactions/#{old}/edit")
      view |> element("#tx-delete") |> render_click()
      assert reload(old).deleted_at
    end

    test "a deleted transaction is not found", c do
      {:ok, _deleted} = Ledger.delete_transaction(c.shopping)

      assert {:error, {:live_redirect, %{to: to, flash: %{"error" => "Buchung nicht gefunden."}}}} =
               live(c.conn, ~p"/accounts/#{c.giro}/transactions/#{c.shopping}/edit")

      assert to == ~p"/accounts/#{c.giro}"
    end

    test "a transaction that never was is not found either", c do
      for id <- [c.shopping.id + 1_000, "x"] do
        assert {:error,
                {:live_redirect, %{to: to, flash: %{"error" => "Buchung nicht gefunden."}}}} =
                 live(c.conn, "/accounts/#{c.giro.id}/transactions/#{id}/edit")

        assert to == ~p"/accounts/#{c.giro}"
      end

      {:ok, view, _html} = live(c.conn, ~p"/accounts/#{c.giro}")
      render_patch(view, "/accounts/#{c.giro.id}/transactions/#{c.shopping.id + 1_000}/edit")
      assert_patch(view, ~p"/accounts/#{c.giro}")
      assert has_element?(view, "#flash-error", "Buchung nicht gefunden")
    end
  end
end
