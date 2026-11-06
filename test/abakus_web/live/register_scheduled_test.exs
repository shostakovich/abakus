defmodule AbakusWeb.RegisterScheduledTest do
  use AbakusWeb.ConnCase

  import Phoenix.LiveViewTest
  import Abakus.DomainFixtures

  alias Abakus.{Ids, Ledger, Repo}
  alias Abakus.Ledger.{Scheduled, ScheduledTransaction, Transaction}

  setup :register_and_log_in_user

  setup do
    fix_today(~D[2026-11-06])
    giro = account_fixture(name: "💶 Girokonto", kind: :checking)
    savings = account_fixture(name: "🏦 Sparkonto", kind: :savings)
    rent = category_fixture(name: "🏠 Miete")
    groceries = category_fixture(name: "🛒 Lebensmittel")
    landlord = payee_fixture(name: "Wohnbau Lindenhof eG")
    %{giro: giro, savings: savings, rent: rent, groceries: groceries, landlord: landlord}
  end

  defp scheduled_fixture(c, attrs \\ []) do
    {:ok, scheduled} =
      Scheduled.create(
        budget_scope(),
        Enum.into(attrs, %{
          account_id: c.giro.id,
          next_date: ~D[2026-12-01],
          repeat_unit: :month,
          repeat_every: 1,
          payee_id: c.landlord.id,
          category_id: c.rent.id,
          amount: -95_000
        })
      )

    scheduled
  end

  defp open_new(view) do
    view |> element("#new-scheduled") |> render_click()
    assert has_element?(view, "#scheduled-dialog h2", "Geplante Buchung")
    view
  end

  defp open_scheduled(view, scheduled) do
    view |> element("#scheduled-#{scheduled.id} .list-col-grow > button") |> render_click()
    assert has_element?(view, "#scheduled-dialog")
    view
  end

  defp change(view, changed, target) do
    view
    |> element("#sched-form")
    |> render_change(Map.put(%{"transaction" => changed}, "_target", ["transaction" | target]))
  end

  defp pick(view, side, field, value) do
    picked = %{"#{field}_pick" => value}

    if side == "main",
      do: change(view, picked, ["#{field}_pick"]),
      else:
        change(view, %{"subtransactions" => %{side => picked}}, [
          "subtransactions",
          side,
          "#{field}_pick"
        ])
  end

  defp submit(view, params),
    do: view |> form("#sched-form", transaction: params) |> render_submit()

  defp only_scheduled do
    [scheduled] = Scheduled.list(budget_scope(), :all)
    Repo.preload(scheduled, :subtransactions, force: true)
  end

  describe "the list" do
    test "shows only while something is planned, collapsed, with its count", c do
      {:ok, view, _html} = live(c.conn, ~p"/budget/accounts/#{c.giro}")
      refute has_element?(view, "#scheduled")

      rent = scheduled_fixture(c)

      scheduled_fixture(c,
        payee_id: nil,
        payee_name: "Gemüsekiste",
        category_id: c.groceries.id,
        amount: -2_490,
        next_date: ~D[2026-12-09],
        repeat_unit: :week,
        repeat_every: 2
      )

      {:ok, view, _html} = live(c.conn, ~p"/budget/accounts/#{c.giro}")
      assert has_element?(view, "#scheduled summary", "Geplant · 2")
      refute has_element?(view, "#scheduled-list[open]")
      refute has_element?(view, "#scheduled-toggle")

      assert has_element?(view, "#scheduled-#{rent.id}", "Wohnbau Lindenhof eG")
      assert has_element?(view, "#scheduled-#{rent.id}", "01.12.")
      assert has_element?(view, "#scheduled-#{rent.id}", "🏠 Miete")
      assert has_element?(view, "#scheduled-#{rent.id}", "Monatlich")
      assert has_element?(view, "#scheduled-#{rent.id}", "−950,00")
      assert has_element?(view, "#scheduled", "Alle 2 Wochen")
      assert has_element?(view, "#scheduled-#{rent.id}-enter")
      assert has_element?(view, "#scheduled-#{rent.id}-skip")

      {:ok, view, _html} = live(c.conn, ~p"/budget/accounts/#{c.savings}")
      refute has_element?(view, "#scheduled")

      {:ok, view, _html} = live(c.conn, ~p"/budget/accounts/all")
      assert has_element?(view, "#scheduled summary", "Geplant · 2")
      assert has_element?(view, "#scheduled-#{rent.id}", "Girokonto")
    end

    test "Ansicht › Geplante Buchungen shows it empty, with „+ Geplante Buchung“", c do
      {:ok, view, _html} = live(c.conn, ~p"/budget/accounts/#{c.giro}")

      view |> element("#scheduled-toggle") |> render_click()

      assert has_element?(view, "#scheduled-list[open]")
      assert has_element?(view, "#scheduled", "Keine geplanten Buchungen")

      assert has_element?(
               view,
               "#scheduled",
               "Wiederkehrende und künftige Buchungen erscheinen hier."
             )

      assert has_element?(view, "#new-scheduled", "Geplante Buchung")
      assert has_element?(view, ~s|#scheduled-toggle[aria-current="true"]|)

      view |> element("#scheduled-toggle") |> render_click()
      refute has_element?(view, "#scheduled")
    end

    test "the Kasse account and closed accounts take no new scheduled transaction", c do
      shared = account_fixture(name: "👫 Geteilt", shared_expenses: true)
      closed = account_fixture(name: "Altes Sparbuch", kind: :savings, closed: true)

      for account <- [shared, closed] do
        {:ok, view, _html} = live(c.conn, ~p"/budget/accounts/#{account}")
        refute has_element?(view, "#scheduled-toggle")
        refute has_element?(view, "#new-scheduled")
        render_click(view, "new_scheduled", %{})
        refute has_element?(view, "#scheduled-dialog")
      end

      kept = scheduled_fixture(c, account_id: closed.id, category_id: nil, payee_id: nil)
      fed = scheduled_fixture(c, account_id: shared.id)

      for {account, scheduled} <- [{closed, kept}, {shared, fed}] do
        {:ok, view, _html} = live(c.conn, ~p"/budget/accounts/#{account}")
        assert has_element?(view, "#scheduled summary", "Geplant · 1")
        refute has_element?(view, "#new-scheduled")
        refute has_element?(view, "#scheduled-#{scheduled.id}-enter")
        assert has_element?(view, "#scheduled-#{scheduled.id}-skip")

        render_click(view, "enter_scheduled", %{id: scheduled.id})
        assert Repo.reload!(scheduled).next_date == ~D[2026-12-01]
        assert Ledger.list_transactions(budget_scope(), account) == []
      end

      {:ok, _} = Scheduled.delete(budget_scope(), fed)

      {:ok, view, _html} = live(c.conn, ~p"/budget/accounts/all")
      open_new(view)

      assert has_element?(view, "#sched-account option", "Girokonto")
      refute has_element?(view, "#sched-account option", "Geteilt")
      refute has_element?(view, "#sched-account option", "Altes Sparbuch")

      view
      |> element("#sched-form")
      |> render_submit(%{
        "transaction" => %{
          "account_id" => shared.id,
          "amount" => "10",
          "date" => "2026-12-01",
          "repeat" => "monthly"
        }
      })

      assert has_element?(view, "#scheduled-dialog", "Muss ausgewählt werden")
      assert [_closed_one] = Scheduled.list(budget_scope(), :all)
    end
  end

  describe "the dialog" do
    test "creates a monthly one in the register's account", c do
      {:ok, view, _html} = live(c.conn, ~p"/budget/accounts/#{c.giro}")
      view |> element("#scheduled-toggle") |> render_click()
      open_new(view)

      assert has_element?(view, ~s|#sched-account option[selected][value="#{c.giro.id}"]|)
      assert has_element?(view, ~s|#sched-date[value="2026-11-06"]|)
      refute has_element?(view, "#sched-delete")

      pick(view, "main", "payee", "p:Wohnbau Lindenhof eG")
      pick(view, "main", "category", c.rent.id)
      change(view, %{"date" => "2026-12-01", "repeat" => "monthly"}, ["repeat"])

      assert has_element?(
               view,
               "#sched-following",
               "Danach: 01.01.2027 · 01.02.2027 · 01.03.2027"
             )

      refute has_element?(view, "#sched-every")

      submit(view, %{amount: "950", memo: "Miete", date: "2026-12-01", repeat: "monthly"})

      refute has_element?(view, "#scheduled-dialog")
      assert has_element?(view, "#flash-info", "Geplante Buchung gespeichert.")

      assert %ScheduledTransaction{
               account_id: account_id,
               next_date: ~D[2026-12-01],
               repeat_unit: :month,
               repeat_every: 1,
               amount: -95_000,
               memo: "Miete",
               payee_id: payee_id,
               category_id: category_id
             } = scheduled = only_scheduled()

      assert {account_id, payee_id, category_id} == {c.giro.id, c.landlord.id, c.rent.id}
      assert has_element?(view, "#scheduled-#{scheduled.id}", "Monatlich")
    end

    test "every 2 weeks shows the three dates after the next one and keeps them on editing", c do
      {:ok, view, _html} = live(c.conn, ~p"/budget/accounts/#{c.giro}")
      view |> element("#scheduled-toggle") |> render_click()
      open_new(view)

      change(view, %{"date" => "2026-12-09", "repeat" => "custom"}, ["repeat"])
      assert has_element?(view, ~s|#sched-every[value="2"]|)
      assert has_element?(view, ~s|#sched-unit input[value="week"][checked]|)

      assert has_element?(
               view,
               "#sched-following",
               "Danach: 23.12.2026 · 06.01.2027 · 20.01.2027"
             )

      change(view, %{"every" => "3", "unit" => "month"}, ["unit"])

      assert has_element?(
               view,
               "#sched-following",
               "Danach: 09.03.2027 · 09.06.2027 · 09.09.2027"
             )

      change(view, %{"every" => "2", "unit_phone" => "week"}, ["unit_phone"])

      assert has_element?(
               view,
               "#sched-following",
               "Danach: 23.12.2026 · 06.01.2027 · 20.01.2027"
             )

      submit(view, %{
        amount: "24,90",
        date: "2026-12-09",
        repeat: "custom",
        every: "2",
        unit: "week",
        unit_phone: "week"
      })

      assert %ScheduledTransaction{repeat_unit: :week, repeat_every: 2, amount: -2_490} =
               scheduled = only_scheduled()

      assert has_element?(view, "#scheduled-#{scheduled.id}", "Alle 2 Wochen")

      open_scheduled(view, scheduled)
      assert has_element?(view, ~s|#sched-repeat option[selected][value="custom"]|)
      assert has_element?(view, ~s|#sched-every[value="2"]|)
      assert has_element?(view, "#sched-following", "Danach: 23.12.2026")

      submit(view, %{repeat: "monthly"})
      assert %{repeat_unit: :month, repeat_every: 1} = only_scheduled()
    end

    test "says what is wrong next to the field", c do
      {:ok, view, _html} = live(c.conn, ~p"/budget/accounts/#{c.giro}")
      view |> element("#scheduled-toggle") |> render_click()
      open_new(view)

      change(view, %{"repeat" => "custom"}, ["repeat"])
      submit(view, %{amount: "60*2", date: "", repeat: "custom", every: "100", unit: "week"})

      assert has_element?(view, "#sched-amount-error-0", "Ungültiger Betrag „60*2“.")
      assert has_element?(view, "#sched-date-error-0", "Muss ausgefüllt werden")
      assert has_element?(view, "#sched-every-error-0", "1 bis 99")
      assert Scheduled.list(budget_scope(), :all) == []
    end

    test "edits a split with the register's parts editor", c do
      {:ok, view, _html} = live(c.conn, ~p"/budget/accounts/#{c.giro}")
      view |> element("#scheduled-toggle") |> render_click()
      open_new(view)

      change(view, %{"amount" => "100"}, ["amount"])
      pick(view, "main", "payee", "p:Wohnbau Lindenhof eG")
      pick(view, "main", "category", "split")
      assert has_element?(view, "#sched-sub-0")
      assert has_element?(view, "#sched-sub-1")

      pick(view, "0", "category", c.rent.id)
      pick(view, "1", "category", c.groceries.id)
      view |> element("#sched-add-sub") |> render_click()
      view |> element("#sched-sub-2-remove") |> render_click()

      submit(view, %{
        amount: "100",
        date: "2026-12-01",
        repeat: "monthly",
        subtransactions: %{
          "0" => %{outflow: "95", memo: "Kaltmiete"},
          "1" => %{outflow: "5", memo: "Nebenkosten"}
        }
      })

      assert %ScheduledTransaction{amount: -10_000, category_id: nil} = split = only_scheduled()

      assert [
               %{amount: -9_500, memo: "Kaltmiete", category_id: rent},
               %{amount: -500, memo: "Nebenkosten", category_id: groceries}
             ] = split.subtransactions

      assert {rent, groceries} == {c.rent.id, c.groceries.id}
      assert has_element?(view, "#scheduled-#{split.id}", "Aufgeteilt (2)")

      open_scheduled(view, split)
      assert has_element?(view, ~s|#sched-sub-0-memo[value="Kaltmiete"]|)
      view |> element("#sched-sub-1-remove") |> render_click()
      submit(view, %{amount: "100"})

      assert %{subtransactions: [], category_id: ^rent} = only_scheduled()
    end

    test "plans a transfer", c do
      {:ok, view, _html} = live(c.conn, ~p"/budget/accounts/#{c.giro}")
      view |> element("#scheduled-toggle") |> render_click()
      open_new(view)

      pick(view, "main", "payee", "a:#{c.savings.id}")
      assert has_element?(view, ~s|#sched-category[placeholder="Keine Kategorie nötig"]|)
      submit(view, %{amount: "200", date: "2026-12-15", repeat: "monthly", memo: "Sparrate"})

      assert %ScheduledTransaction{amount: -20_000, category_id: nil} =
               transfer = only_scheduled()

      assert transfer.payee_id == c.savings.transfer_payee.id
      assert has_element?(view, "#scheduled-#{transfer.id}", "⇄ 🏦 Sparkonto")
    end

    test "plans a transfer with a tracking account in the budget account", c do
      depot = account_fixture(name: "📈 Depot", kind: :tracking)
      {:ok, view, _html} = live(c.conn, ~p"/budget/accounts/#{depot}")
      view |> element("#scheduled-toggle") |> render_click()
      open_new(view)

      pick(view, "main", "payee", "a:#{c.giro.id}")
      pick(view, "main", "category", c.rent.id)
      submit(view, %{amount: "200", date: "2026-12-15", repeat: "monthly"})

      assert has_element?(view, "#scheduled-dialog", "Wird im Budgetkonto geplant")
      assert Scheduled.list(budget_scope(), :all) == []
    end

    test "offers no transfer to the Kasse account", c do
      shared = account_fixture(name: "👫 Geteilt", shared_expenses: true)
      {:ok, view, _html} = live(c.conn, ~p"/budget/accounts/#{c.giro}")
      view |> element("#scheduled-toggle") |> render_click()
      open_new(view)

      payees = view |> element("#sched-payee-list") |> render()
      assert payees =~ "a:#{c.savings.id}"
      refute payees =~ "a:#{shared.id}"
    end

    test "opens none for another user's id", c do
      theirs = Abakus.UsersFixtures.user_scope_fixture()
      {:ok, account} = Ledger.create_account(theirs, %{name: "Fremd", kind: :checking})

      {:ok, foreign} =
        Scheduled.create(theirs, %{
          account_id: account.id,
          next_date: ~D[2026-12-01],
          amount: -100
        })

      {:ok, view, _html} = live(c.conn, ~p"/budget/accounts/#{c.giro}")
      render_click(view, "edit_scheduled", %{id: foreign.id})

      refute has_element?(view, "#scheduled-dialog")
      assert has_element?(view, "#flash-error", "Die geplante Buchung gibt es nicht mehr.")
    end

    test "deletes after asking", c do
      scheduled = scheduled_fixture(c)
      {:ok, view, _html} = live(c.conn, ~p"/budget/accounts/#{c.giro}")
      open_scheduled(view, scheduled)

      assert asked(view, "#sched-delete").question == "Geplante Buchung löschen?"
      confirm_click(view, "#sched-delete")

      assert Repo.reload!(scheduled).deleted_at
      refute has_element?(view, "#scheduled")
      assert has_element?(view, "#flash-info", "Geplante Buchung gelöscht.")
    end
  end

  describe "a row" do
    test "„Jetzt buchen“ enters it approved with the job's id; the job does not enter it again",
         c do
      scheduled = scheduled_fixture(c, next_date: ~D[2026-11-06])
      {:ok, view, _html} = live(c.conn, ~p"/budget/accounts/#{c.giro}")

      view |> element("#scheduled-#{scheduled.id}-enter") |> render_click()

      assert has_element?(view, "#flash-info", "Gebucht.")
      id = Ids.entered_transaction(scheduled.id, ~D[2026-11-06])

      assert %Transaction{approved: true, amount: -95_000, date: ~D[2026-11-06]} =
               Repo.get!(Transaction, id)

      assert has_element?(view, "#tx-#{id}")
      assert Repo.reload!(scheduled).next_date == ~D[2026-12-06]
      assert has_element?(view, "#scheduled-#{scheduled.id}", "06.12.")

      assert Scheduled.enter_due(budget_scope(), ~D[2026-11-06]) == {:ok, 0}
      assert [_once] = Ledger.list_transactions(budget_scope(), c.giro)
    end

    test "„Überspringen“ moves on without entering it", c do
      scheduled = scheduled_fixture(c)
      {:ok, view, _html} = live(c.conn, ~p"/budget/accounts/#{c.giro}")

      view |> element("#scheduled-#{scheduled.id}-skip") |> render_click()

      assert has_element?(view, "#flash-info", "Übersprungen.")
      assert Repo.reload!(scheduled).next_date == ~D[2027-01-01]
      assert has_element?(view, "#scheduled-#{scheduled.id}", "01.01.")
      assert Ledger.list_transactions(budget_scope(), c.giro) == []
    end
  end
end
