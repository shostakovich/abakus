defmodule AbakusWeb.Kasse.BudgetLinkLiveTest do
  use AbakusWeb.ConnCase

  import Phoenix.LiveViewTest
  import Abakus.DomainFixtures
  import Abakus.KasseFixtures
  import AbakusWeb.PageText

  alias Abakus.Kasse.{BudgetLink, Expenses, Ynab}
  alias Abakus.Kasse.BudgetLink.LinkedTransaction
  alias Abakus.Kasse.Ynab.Posting
  alias Abakus.Ledger.Transaction
  alias Abakus.Repo
  alias Setzkasten.Test.Confirm

  setup %{conn: conn} do
    h = household()
    account = account_fixture(name: "👫 Geteilt", kind: :cash, fed_by: :shared_expenses)
    groceries = category_fixture(name: "🛒 Lebensmittel")
    treats = category_fixture(name: "🍷 Genuss")

    %{
      h: h,
      conn: conn |> log_in_participant(h.anna),
      account: account,
      groceries: groceries,
      treats: treats
    }
  end

  defp link!(c) do
    {:ok, _mapping} =
      BudgetLink.put_category_mapping(scope_of(c.h.anna), %{c.h.food => c.groceries.id})

    {:ok, _anna} = BudgetLink.switch_on(scope_of(c.h.anna), c.account.id)

    expense =
      create!(equal(c.h, "Wocheneinkauf", 8742, "2026-10-12", c.h.ben, [c.h.anna, c.h.ben]))

    link = Repo.get_by!(LinkedTransaction, expense_id: expense.id)
    %{expense: expense, transaction: Repo.get!(Transaction, link.transaction_id)}
  end

  describe "the budget page" do
    test "maps the Kasse categories to the budget's", c do
      {:ok, view, _html} = live(c.conn, ~p"/settings/kasse/budget")

      assert has_element?(view, "#budget-link-state", "Noch nicht")

      view
      |> form("#budget-mapping-form", mapping: %{"#{c.h.food}" => "#{c.groceries.id}"})
      |> render_submit()

      assert has_element?(view, "#flash-info", "gespeichert")
      assert BudgetLink.category_mapping(scope_of(c.h.anna)) == %{c.h.food => c.groceries.id}

      assert has_element?(
               view,
               ~s|#mapping_#{c.h.food} option[selected][value="#{c.groceries.id}"]|
             )
    end

    test "links to the register once linked", c do
      link!(c)
      {:ok, view, _html} = live(c.conn, ~p"/settings/kasse/budget")

      assert has_element?(
               view,
               ~s|#budget-link-state a[href="/budget/accounts/#{c.account.id}"]|,
               "Geteilt"
             )
    end

    test "is the budget owner's alone", c do
      conn = log_in_participant(c.conn, c.h.ben)
      assert_error_sent 404, fn -> get(conn, ~p"/settings/kasse/budget") end
    end
  end

  describe "switching from YNAB" do
    setup c do
      Repo.insert!(%Ynab.Connection{
        participant_id: c.h.anna,
        token: "token",
        plan_id: "plan",
        account_id: "geteilt",
        start_date: ~D[2026-03-01]
      })

      :ok
    end

    test "links the imported transactions, books the rest and removes the YNAB connection", c do
      {:ok, _mapping} =
        BudgetLink.put_category_mapping(scope_of(c.h.anna), %{c.h.food => c.groceries.id})

      weekly =
        create!(equal(c.h, "Wocheneinkauf", 8742, "2026-03-05", c.h.ben, [c.h.anna, c.h.ben]))

      cinema = create!(equal(c.h, "Kino", 2400, "2026-03-10", c.h.ben, [c.h.anna, c.h.ben]))

      imported =
        transaction_fixture(%{
          account_id: c.account.id,
          date: weekly.date,
          amount: -4371,
          payee_name: "Wocheneinkauf",
          memo: Posting.memo(weekly),
          category_id: c.treats.id,
          cleared: :reconciled,
          approved: true,
          source: :ynab
        })

      {:ok, view, _html} = live(c.conn, ~p"/settings/kasse/budget")

      assert has_element?(view, "#budget-link-ynab", "seit dem 01.03.2026")
      assert has_element?(view, "#budget-mapping-ynab", "Erst nach dem letzten YNAB-Import")
      assert has_element?(view, ~s|#link_account_id option[selected][value="#{c.account.id}"]|)
      assert has_element?(view, "#settings-kasse-ynab-sidebar")

      Confirm.confirm_click(view, "#budget-link-submit", "Mit Budget verknüpfen?")
      refute has_element?(view, "#settings-kasse-ynab-sidebar")

      assert has_element?(
               view,
               "#flash-info",
               "Mit dem Budget verknüpft: 1 Buchung übernommen, 1 Buchung neu angelegt."
             )

      assert has_element?(view, ~s|#budget-link-state a[href="/budget/accounts/#{c.account.id}"]|)
      refute has_element?(view, "#budget-link-form")

      assert %{transaction_id: imported_id} =
               Repo.get_by!(LinkedTransaction, expense_id: weekly.id)

      assert imported_id == imported.id

      assert %{category_id: treats, cleared: :reconciled, approved: true} =
               Repo.reload!(imported)

      assert treats == c.treats.id

      assert %{transaction_id: created_id} =
               Repo.get_by!(LinkedTransaction, expense_id: cinema.id)

      assert %{amount: -1200, approved: false} = Repo.get!(Transaction, created_id)

      assert Repo.all(Ynab.Connection) == []
    end

    test "counts the marked transactions it could not take over", c do
      weekly =
        create!(equal(c.h, "Wocheneinkauf", 8742, "2026-03-05", c.h.ben, [c.h.anna, c.h.ben]))

      gone = create!(equal(c.h, "Pizza", 2000, "2026-03-06", c.h.ben, [c.h.anna, c.h.ben]))

      for expense <- [weekly, weekly, gone] do
        transaction_fixture(%{
          account_id: c.account.id,
          date: expense.date,
          amount: -1000,
          memo: Posting.memo(expense),
          source: :ynab
        })
      end

      {:ok, _deleted} = Expenses.delete_expense(scope_of(c.h.ben), gone)
      {:ok, view, _html} = live(c.conn, ~p"/settings/kasse/budget")

      Confirm.confirm_click(view, "#budget-link-submit", "Mit Budget verknüpfen?")

      assert flash(view, :info) ==
               "Mit dem Budget verknüpft: 1 Buchung übernommen, 0 Buchungen neu angelegt. " <>
                 "Unverknüpft geblieben: 1 Buchung mit Kasse-Kennung, die sich nicht übernehmen ließ " <>
                 "(Aufteilung, Umbuchung oder doppelt) – bitte von Hand prüfen; " <>
                 "1 Buchung mit Kasse-Kennung ohne passende Ausgabe."
    end

    test "asks for an account", c do
      {:ok, view, _html} = live(c.conn, ~p"/settings/kasse/budget")

      Confirm.confirm_click(view, "#budget-link-submit", nil,
        with: %{"link" => %{"account_id" => ""}}
      )

      assert has_element?(view, "#flash-error", "Bitte ein offenes Budget-Konto wählen.")
      assert Repo.get(Ynab.Connection, c.h.anna)
    end

    test "offers YNAB no longer once linked", c do
      link!(c)

      {:ok, view, _html} = live(c.conn, ~p"/settings/kasse")
      assert has_element?(view, "#settings-kasse-budget-sidebar")
      refute has_element?(view, "#settings-kasse-ynab-sidebar")

      assert_raise AbakusWeb.NotFoundError, fn -> live(c.conn, ~p"/settings/kasse/ynab") end
    end
  end

  describe "a linked expense" do
    test "shows the budget owner its category in the budget and links to the register", c do
      %{expense: expense} = link!(c)
      {:ok, view, _html} = live(c.conn, ~p"/kasse/expenses/#{expense}")

      assert has_element?(view, "#expense-budget-facts", "43,71")
      assert has_element?(view, "#expense-budget-facts", "🛒 Lebensmittel")
      assert has_element?(view, ~s|#expense-register[href="/budget/accounts/#{c.account.id}"]|)
    end

    test "shows the other members nothing of the budget", c do
      %{expense: expense} = link!(c)

      {:ok, view, _html} =
        live(log_in_participant(c.conn, c.h.ben), ~p"/kasse/expenses/#{expense}")

      refute has_element?(view, "#expense-budget")
    end
  end

  describe "the register" do
    defp open_edit(view, transaction) do
      view |> element("#tx-#{transaction.id} td.app-payee") |> render_click()
      view |> element("#tx-#{transaction.id} td.app-payee") |> render_click()
      assert has_element?(view, "#tx-editor")
      view
    end

    test "offers no reconcile for the shared-expenses account", c do
      {:ok, view, _html} = live(c.conn, ~p"/budget/accounts/#{c.account}")
      refute has_element?(view, "#reconcile-open")
      render_click(view, "reconcile_open", %{})
      refute has_element?(view, "#reconcile-question")
    end

    test "edits only category, memo, flag and approval of a linked transaction", c do
      %{expense: expense, transaction: transaction} = link!(c)
      {:ok, view, _html} = live(c.conn, ~p"/budget/accounts/#{c.account}")
      open_edit(view, transaction)

      assert has_element?(view, ~s|#tx-expense-link[href="/kasse/expenses/#{expense.id}"]|)

      for field <- ~w(tx-date tx-outflow tx-inflow) do
        assert has_element?(view, "##{field}[disabled]")
      end

      assert has_element?(view, "#tx-payee-combobox input[disabled]")

      view
      |> element("#tx-form")
      |> render_change(%{
        "transaction" => %{"category_pick" => "#{c.treats.id}"},
        "_target" => ["transaction", "category_pick"]
      })

      view
      |> element("#tx-form")
      |> render_submit(%{
        "transaction" => %{"memo" => "Spargel", "outflow" => "99", "date" => "2026-01-01"}
      })

      assert %{
               amount: -4371,
               date: ~D[2026-10-12],
               memo: "Spargel",
               category_id: treats,
               approved: true
             } = Repo.reload!(transaction)

      assert treats == c.treats.id
    end

    test "deletes a linked transaction only with its expense", c do
      %{transaction: transaction} = link!(c)
      {:ok, view, _html} = live(c.conn, ~p"/budget/accounts/#{c.account}")

      render_click(view, "select", %{"id" => "#{transaction.id}"})
      render_click(view, "delete_selected", %{})
      assert has_element?(view, "#flash-error", "mit ihrer Ausgabe gelöscht")

      render_click(view, "clear_selection", %{})
      open_edit(view, transaction)
      refute has_element?(view, "#tx-delete")
      view |> with_target("#tx-editor") |> render_click("delete", %{})
      assert has_element?(view, "#tx-error", "mit ihrer Ausgabe gelöscht")

      refute Repo.reload!(transaction).deleted_at
    end
  end
end
