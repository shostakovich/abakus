defmodule AbakusWeb.Kasse.BudgetLinkLiveTest do
  use AbakusWeb.ConnCase

  import Ecto.Query
  import Phoenix.LiveViewTest
  import Abakus.DomainFixtures
  import Abakus.KasseFixtures
  import AbakusWeb.PageText

  alias Abakus.Kasse.{BudgetLink, Expenses}
  alias Abakus.Kasse.Expenses.Expense
  alias Abakus.Ledger
  alias Abakus.Ledger.Transaction
  alias Abakus.Repo
  alias Setzkasten.Test.Confirm

  setup %{conn: conn} do
    h = household()
    account = account_fixture(name: "👫 Geteilt", kind: :cash, shared_expenses: true)
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

    %{expense: expense, transaction: Repo.get_by!(Transaction, kasse_expense_id: expense.id)}
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
               "Jede bisherige Ausgabe und Rückzahlung, die deinen Saldo ändert, bekommt eine Buchung."
             )

      assert has_element?(view, ~s|#link_account_id option[selected][value="#{c.account.id}"]|)

      Confirm.confirm_click(view, "#budget-link-submit", "Mit Budget verknüpfen?")

      assert flash(view, :info) == "Mit dem Budget verknüpft: 2 Buchungen angelegt."
      assert has_element?(view, ~s|#budget-link-state a[href="/budget/accounts/#{c.account.id}"]|)
      refute has_element?(view, "#budget-link-form")

      for {expense, amount} <- [{weekly, -4371}, {cinema, -1200}] do
        assert %{amount: ^amount, approved: false} =
                 Repo.get_by!(Transaction, kasse_expense_id: expense.id)
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

    test "shows the account of a reimbursement", c do
      link!(c)
      payback = create!(reimbursement(2500, "2026-10-12", c.h.ben, c.h.anna), c.h.ben)
      {:ok, view, _html} = live(c.conn, ~p"/kasse/expenses/#{payback}")

      assert has_element?(view, "#expense-budget-facts", "Noch offen")
      refute has_element?(view, "#expense-budget-facts", "Kategorie")
    end

    test "shows the other members nothing of the budget", c do
      %{expense: expense} = link!(c)

      {:ok, view, _html} =
        live(log_in_participant(c.conn, c.h.ben), ~p"/kasse/expenses/#{expense}")

      refute has_element?(view, "#expense-budget")
    end
  end

  describe "a reimbursement" do
    setup c do
      link!(c)
      %{checking: account_fixture(name: "Checking", kind: :checking)}
    end

    defp submit_expense(view, params),
      do: view |> form("#expense-form", expense: params) |> render_submit()

    defp led_transfer(account),
      do:
        Repo.one!(
          from t in Transaction,
            where: t.account_id == ^account.id and is_nil(t.deleted_at),
            preload: :payee
        )

    test "asks the budget owner for the account, also from a suggestion", c do
      path =
        ~p"/kasse/expenses/new?#{[reimbursement: 1, from: c.h.anna, to: c.h.ben, amount: 3000]}"

      {:ok, view, _html} = live(c.conn, path)

      assert has_element?(view, "#expense_budget_account_id option", "Noch offen")
      assert has_element?(view, "#expense_budget_account_id option", "Checking")
      refute has_element?(view, "#expense_budget_account_id option", "Geteilt")

      submit_expense(view, %{budget_account_id: "#{c.checking.id}"})
      assert_redirect(view, ~p"/kasse")

      assert %{amount: -3000, payee: %{transfer_account_id: shared}} = led_transfer(c.checking)
      assert shared == c.account.id
    end

    test "chooses the account of one the other person recorded", c do
      payback = create!(reimbursement(2500, "2026-10-12", c.h.ben, c.h.anna), c.h.ben)
      {:ok, view, _html} = live(c.conn, ~p"/kasse/expenses/#{payback}")

      assert has_element?(view, "#expense_budget_account_id")
      refute has_element?(view, "#expense_budget_account_id option[selected]")
      submit_expense(view, %{budget_account_id: "#{c.checking.id}"})
      assert_redirect(view, ~p"/kasse")

      assert %{amount: 2500} = led_transfer(c.checking)

      {:ok, view, _html} = live(c.conn, ~p"/kasse/expenses/#{payback}")
      assert has_element?(view, "#expense_budget_account_id option[selected]", "Checking")
    end

    test "keeps an account closed since when saved again", c do
      payback = create!(reimbursement(2500, "2026-10-12", c.h.ben, c.h.anna), c.h.ben)

      {:ok, _payback} =
        Expenses.update_expense(
          scope_of(c.h.anna),
          payback,
          Expenses.input(payback),
          budget_account_id: c.checking.id
        )

      {:ok, _closed} = Ledger.update_account(budget_scope(), c.checking, %{closed: true})
      {:ok, view, _html} = live(c.conn, ~p"/kasse/expenses/#{payback}")

      assert has_element?(view, "#expense_budget_account_id option[selected]", "Checking")
      submit_expense(view, %{notes: "Bar"})
      assert_redirect(view, ~p"/kasse")

      assert %{amount: 2500} = led_transfer(c.checking)
    end

    test "asks only when it involves the budget owner", c do
      {:ok, view, _html} =
        live(c.conn, ~p"/kasse/expenses/new?#{[reimbursement: 1, from: c.h.ben, to: c.h.cleo]}")

      refute has_element?(view, "#expense_budget_account_id")

      {:ok, view, _html} =
        live(
          log_in_participant(c.conn, c.h.ben),
          ~p"/kasse/expenses/new?#{[reimbursement: 1, to: c.h.anna]}"
        )

      refute has_element?(view, "#expense_budget_account_id")
    end

    test "booked as a transfer in the register asks for the person", c do
      {:ok, view, _html} = live(c.conn, ~p"/budget/accounts/#{c.checking}")
      view |> element("#new-transaction") |> render_click()
      refute has_element?(view, "#tx-person")

      view
      |> element("#tx-form")
      |> render_change(%{
        "transaction" => %{"payee_pick" => "a:#{c.account.id}"},
        "_target" => ["transaction", "payee_pick"]
      })

      assert has_element?(view, "#tx-person option", "Ben")
      assert has_element?(view, "#tx-person option", "Cleo")

      view |> form("#tx-form", transaction: %{amount: "30"}) |> render_submit()
      assert has_element?(view, "#tx-error", "mit wem in der Kasse")

      view
      |> form("#tx-form", transaction: %{amount: "30", person_id: "#{c.h.cleo}"})
      |> render_submit()

      refute has_element?(view, "#tx-editor")

      assert %Expense{paid_by_id: anna, amount_cents: 3000} =
               Repo.one!(from e in Expense, where: e.reimbursement)

      assert anna == c.h.anna
    end

    test "a transfer moved past the link's start date asks for the person", c do
      Repo.update_all(BudgetLink.Link, set: [start_date: ~D[2026-10-01]])

      {:ok, transfer} =
        Ledger.create_transaction(budget_scope(), %{
          account_id: c.checking.id,
          date: ~D[2026-09-20],
          amount: -3000,
          payee_id: c.account.transfer_payee.id,
          approved: true
        })

      {:ok, view, _html} = live(c.conn, ~p"/budget/accounts/#{c.checking}")
      view |> element("#tx-#{transfer.id} td.app-payee") |> render_click()
      view |> element("#tx-#{transfer.id} td.app-payee") |> render_click()
      refute has_element?(view, "#tx-person")

      view
      |> element("#tx-form")
      |> render_change(%{
        "transaction" => %{"date" => "2026-10-12"},
        "_target" => ["transaction", "date"]
      })

      assert has_element?(view, "#tx-person option", "Cleo")
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

      for field <- ~w(tx-date tx-sign tx-amount) do
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
        "transaction" => %{"memo" => "Spargel", "amount" => "99", "date" => "2026-01-01"}
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

      render_click(view, "row_click", %{"id" => "#{transaction.id}", "toggle" => true})
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
