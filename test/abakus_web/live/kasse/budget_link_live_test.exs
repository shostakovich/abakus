defmodule AbakusWeb.Kasse.BudgetLinkLiveTest do
  use AbakusWeb.ConnCase

  import Phoenix.LiveViewTest
  import Abakus.DomainFixtures
  import Abakus.KasseFixtures
  import AbakusWeb.PageText

  alias Abakus.Kasse.BudgetLink
  alias Abakus.Kasse.BudgetLink.LinkedTransaction
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

  describe "switching on" do
    test "books every expense and links to the register", c do
      {:ok, _mapping} =
        BudgetLink.put_category_mapping(scope_of(c.h.anna), %{c.h.food => c.groceries.id})

      weekly =
        create!(equal(c.h, "Wocheneinkauf", 8742, "2026-03-05", c.h.ben, [c.h.anna, c.h.ben]))

      cinema = create!(equal(c.h, "Kino", 2400, "2025-03-10", c.h.ben, [c.h.anna, c.h.ben]))

      {:ok, view, _html} = live(c.conn, ~p"/settings/kasse/budget")

      assert has_element?(
               view,
               "#budget-link-state",
               "Jede bisherige Ausgabe, die deinen Saldo ändert, bekommt eine Buchung."
             )

      assert has_element?(view, ~s|#link_account_id option[selected][value="#{c.account.id}"]|)

      Confirm.confirm_click(view, "#budget-link-submit", "Mit Budget verknüpfen?")

      assert flash(view, :info) == "Mit dem Budget verknüpft: 2 Buchungen angelegt."
      assert has_element?(view, ~s|#budget-link-state a[href="/budget/accounts/#{c.account.id}"]|)
      refute has_element?(view, "#budget-link-form")

      for {expense, amount} <- [{weekly, -4371}, {cinema, -1200}] do
        linked = Repo.get_by!(LinkedTransaction, expense_id: expense.id)
        assert %{amount: ^amount, approved: false} = Repo.get!(Transaction, linked.transaction_id)
      end
    end

    test "asks for an account", c do
      {:ok, view, _html} = live(c.conn, ~p"/settings/kasse/budget")

      Confirm.confirm_click(view, "#budget-link-submit", nil,
        with: %{"link" => %{"account_id" => ""}}
      )

      assert has_element?(view, "#flash-error", "Bitte ein offenes Budget-Konto wählen.")
      assert BudgetLink.account(scope_of(c.h.anna)) == nil
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

    test "edits only category, memo and approval of a linked transaction", c do
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
