defmodule AbakusWeb.BudgetDetailsTest do
  use AbakusWeb.ConnCase

  import Phoenix.LiveViewTest
  import Abakus.DomainFixtures

  alias Abakus.{Categories, Ledger}
  alias Setzkasten.Test.Confirm

  @october ~D[2026-10-01]
  @november ~D[2026-11-01]

  setup :register_and_log_in_user
  setup do: fix_today(~D[2026-10-10])

  setup do
    checking = account_fixture(kind: :checking)
    rta = Categories.ready_to_assign!(budget_scope())
    daily = category_group_fixture(name: "🛒 Alltag", position: 0)
    housing = category_group_fixture(name: "🏠 Wohnen", position: 1)

    groceries =
      category_fixture(name: "🛒 Lebensmittel", category_group_id: daily.id, position: 0)

    fuel = category_fixture(name: "⛽ Tanken", category_group_id: daily.id, position: 1)
    rent = category_fixture(name: "🏠 Miete", category_group_id: housing.id)

    %{checking: checking, rta: rta, groceries: groceries, fuel: fuel, rent: rent}
  end

  describe "a month" do
    test "its card adds up to Zu verteilen, last month's overspending and later months included",
         c do
      income(c, 100_000, ~D[2026-09-01])
      spend(c, c.groceries, -2_500, ~D[2026-09-15])
      income(c, 50_000)
      Categories.assign(budget_scope(), c.groceries, @october, 10_000)
      Categories.assign(budget_scope(), c.rent, @november, 30_000)

      {:ok, view, _html} = open(c.conn, months: 3, path: ~p"/budget?month=2026-09")

      assert calculation(view, "2026-10") == [
               {"Nicht verteilt im Sep", "1000.00"},
               {"Überzogen im Sep", "-25.00"},
               {"Einnahmen im Okt", "500.00"},
               {"Zugewiesen im Okt", "-100.00"},
               {"Für spätere Monate", "-300.00"}
             ]

      assert has_element?(view, "#month-2026-10 .app-mtotal", "Zu verteilen")

      for key <- ~w(2026-09 2026-10 2026-11) do
        assert sum(calculation(view, key)) == ready(view, key)
      end

      assert ready(view, "2026-10") == Decimal.new("1075.00")
      refute has_element?(view, "#calc-2026-11", "Für spätere Monate")
      refute has_element?(view, "#calc-2026-09", "Für spätere Monate")
      assert has_element?(view, "#month-2026-09 .app-mtotal", "Nicht verteilt am Monatsende")
    end

    test "Unterfinanziert fills every target's share as far as Zu verteilen reaches", c do
      income(c, 60_000)
      monthly(c.groceries, 40_000)
      by_date(c.rent, 120_000, ~D[2027-06-01])
      {:ok, view, _html} = open(c.conn)

      assert has_element?(
               view,
               "#distribute-underfunded-2026-10",
               "Unterfinanzierte füllen (533,34 €)"
             )

      view |> element("#distribute-underfunded-2026-10") |> render_click()

      assert assigned(c.groceries, @october) == 40_000
      assert assigned(c.rent, @october) == 13_334
      assert has_element?(view, "#flash-info", "Unterfinanzierte Ziele gefüllt.")

      income(c, 50_000, @november)
      monthly(c.fuel, 50_000)

      {:ok, view, _html} = open(c.conn, months: 2)
      view |> element("#distribute-underfunded-2026-11") |> render_click()

      assert assigned(c.groceries, @november) == 40_000
      assert assigned(c.fuel, @november) == 16_666
      assert assigned(c.rent, @november) == 0
      assert has_element?(view, "#flash-info", "Nur teilweise gefüllt")
    end

    test "Verteilen › Zuweisung zurücksetzen takes back what the month has assigned, after asking",
         c do
      Categories.assign(budget_scope(), c.groceries, @october, 10_000)
      Categories.assign(budget_scope(), c.rent, @october, 20_000)
      Categories.assign(budget_scope(), c.rent, @november, 20_000)
      {:ok, view, _html} = open(c.conn)

      refute has_element?(view, "#distribute-underfunded-2026-10")

      Confirm.confirm_click(
        view,
        "#distribute-reset-2026-10",
        "Alle Zuweisungen im Oktober zurücksetzen?"
      )

      assert assigned(c.groceries, @october) == 0
      assert assigned(c.rent, @october) == 0
      assert assigned(c.rent, @november) == 20_000
      assert has_element?(view, "#flash-info", "Zuweisungen im Oktober zurückgesetzt.")
      refute has_element?(view, "#distribute-2026-10")
    end

    test "Verteilen › In eine Kategorie … assigns Zu verteilen to the category picked", c do
      income(c, 100_000)
      monthly(c.fuel, 12_000)
      {:ok, view, _html} = open(c.conn)

      view |> element("#distribute-pick-2026-10") |> render_click()

      assert has_element?(view, "#popover", "In eine Kategorie verteilen · Oktober")

      assert has_element?(
               view,
               ~s|#pick-category-listbox [data-value="#{c.fuel.id}"][data-current]|
             )

      assert has_element?(view, ~s|#pick-amount[value="120,00"]|)

      view
      |> form("#pick-form")
      |> render_change(%{"_target" => ["category"], "category" => "#{c.rent.id}"})

      assert has_element?(view, ~s|#pick-amount[value="1.000,00"]|)

      view
      |> form("#pick-form", %{"amount" => "250"})
      |> render_submit(%{"category" => "#{c.rent.id}"})

      assert assigned(c.rent, @october) == 25_000
      assert has_element?(view, "#flash-info", "250,00 € an 🏠 Miete verteilt.")
      assert has_element?(view, "#ready-2026-10", "750,00 €")
    end

    test "Verteilen offers to fill the underfunded only while a target is underfunded", c do
      income(c, 5_000)
      {:ok, view, _html} = open(c.conn)

      assert has_element?(view, "#distribute-pick-2026-10")
      refute has_element?(view, "#distribute-underfunded-2026-10")
    end

    test "a closed month offers no Verteilen when later months assigned what it left", c do
      income(c, 5_000, ~D[2026-09-01])
      Categories.assign(budget_scope(), c.fuel, @october, 5_000)

      {:ok, view, _html} = live(c.conn, ~p"/budget?month=2026-09")

      assert has_element?(view, "#ready-2026-09", "50,00")
      refute has_element?(view, "#distribute-2026-09")
    end

    test "Verteilen offers to fill the underfunded only while money is unassigned", c do
      monthly(c.fuel, 12_000)
      {:ok, view, _html} = open(c.conn)

      refute has_element?(view, "#distribute-2026-10")

      income(c, 5_000)
      {:ok, view, _html} = open(c.conn)

      refute has_element?(view, "#distribute-reset-2026-10")
      view |> element("#distribute-underfunded-2026-10") |> render_click()

      assert assigned(c.fuel, @october) == 5_000
      assert has_element?(view, "#distribute-reset-2026-10")
    end
  end

  describe "the available cell" do
    test "covers an overspent category from Zu verteilen", c do
      income(c, 100_000)
      spend(c, c.fuel, -2_500)
      {:ok, view, _html} = open(c.conn)

      view |> element("#available-button-#{c.fuel.id}-2026-10") |> render_click()

      assert has_element?(view, "#popover", "⛽ Tanken")

      assert has_element?(
               view,
               ~s|#cover-from-listbox [data-value=rta][data-current]|,
               "1.000,00 €"
             )

      assert has_element?(view, "#cover-after", "Zu verteilen danach")
      assert has_element?(view, "#cover-after", "975,00 €")

      view |> form("#cover-form") |> render_submit()

      assert assigned(c.fuel, @october) == 2_500
      refute has_element?(view, ~s|#popover[data-show="true"]|)
      assert has_element?(view, "#flash-info", "25,00 € aus „Zu verteilen“ gedeckt.")
    end

    test "moves money to another category or to Zu verteilen", c do
      Categories.assign(budget_scope(), c.groceries, @october, 10_000)
      {:ok, view, _html} = open(c.conn)

      view |> element("#available-button-#{c.groceries.id}-2026-10") |> render_click()

      assert has_element?(view, "#popover", "🛒 Lebensmittel")
      refute has_element?(view, "#popover-cover")
      assert has_element?(view, ~s|#move-amount[value="100,00"]|)
      assert has_element?(view, "#move-form input[name=direction][value=to][checked]")

      view
      |> form("#move-form", %{"amount" => "30", "direction" => "to"})
      |> render_submit(%{"other" => "#{c.rent.id}"})

      assert assigned(c.groceries, @october) == 7_000
      assert assigned(c.rent, @october) == 3_000

      assert has_element?(
               view,
               "#flash-info",
               "30,00 € von 🛒 Lebensmittel nach 🏠 Miete verschoben."
             )

      view |> element("#available-button-#{c.rent.id}-2026-10") |> render_click()

      view
      |> form("#move-form", %{"amount" => "10", "direction" => "from"})
      |> render_submit()

      assert assigned(c.rent, @october) == 4_000
    end

    test "refuses Ready to Assign as a category and ids it cannot read", c do
      hidden = Categories.ready_to_assign!(budget_scope())
      Categories.assign(budget_scope(), c.groceries, @october, 10_000)
      {:ok, view, _html} = open(c.conn)

      id = "#{c.groceries.id}"
      render_hook(view, "move", %{"category" => id, "other" => "#{hidden.id}", "amount" => "5"})
      render_hook(view, "pick", %{"category" => "#{hidden.id}", "amount" => "5"})
      render_hook(view, "pick", %{"amount" => "5"})
      render_hook(view, "cover", %{"category" => id, "from" => %{"a" => "1"}})
      render_hook(view, "move", %{"category" => %{}, "other" => "rta", "amount" => "5"})
      render_hook(view, "pick_change", %{"_target" => ["amount"]})

      assert assigned(hidden, @october) == 0
      assert assigned(c.groceries, @october) == 10_000
      assert render(view) =~ "Lebensmittel"
    end

    test "an amount that is no number stays in the popover with a message", c do
      Categories.assign(budget_scope(), c.groceries, @october, 10_000)
      {:ok, view, _html} = open(c.conn)

      view |> element("#available-button-#{c.groceries.id}-2026-10") |> render_click()

      view
      |> form("#move-form", %{"amount" => "viel", "direction" => "to"})
      |> render_submit()

      assert has_element?(view, "#popover #move-amount-error-0", "Ungültiger Betrag „viel“.")
      assert has_element?(view, "#move-amount[aria-invalid=true]")
      assert assigned(c.groceries, @october) == 10_000

      view
      |> form("#move-form", %{"amount" => "1,234", "direction" => "to"})
      |> render_submit()

      assert has_element?(
               view,
               "#popover #move-amount-error-0",
               "Höchstens 2 Nachkommastellen erlaubt."
             )

      view |> form("#move-form", %{"amount" => "0", "direction" => "to"}) |> render_submit()

      assert has_element?(view, "#popover #move-amount-error-0", "über null")
    end

    test "covers overspending from another category, as far as it has", c do
      Categories.assign(budget_scope(), c.groceries, @october, 1_000)
      spend(c, c.fuel, -2_500)
      {:ok, view, _html} = open(c.conn)

      view |> element("#available-button-#{c.fuel.id}-2026-10") |> render_click()

      assert has_element?(view, "#popover-mode button[aria-pressed=true]", "Decken")
      refute has_element?(view, "#cover-from option[value=rta]")

      view |> form("#cover-form") |> render_change(%{"from" => "#{c.groceries.id}"})

      assert has_element?(view, "#cover-after", "Lebensmittel danach")
      assert has_element?(view, "#cover-after", "0,00 €")

      view |> form("#cover-form") |> render_submit(%{"from" => "#{c.groceries.id}"})

      assert assigned(c.groceries, @october) == 0
      assert assigned(c.fuel, @october) == 1_000

      view |> element("#available-button-#{c.fuel.id}-2026-10") |> render_click()
      view |> element("#popover-mode button", "Verschieben") |> render_click()

      assert has_element?(view, "#move-form")
      assert has_element?(view, "#move-form input[name=direction][value=from][checked]")
    end

    test "closes on cancel, and a click away closes only its own popover", c do
      {:ok, view, _html} = open(c.conn)

      view |> element("#available-button-#{c.groceries.id}-2026-10") |> render_click()
      render_hook(view, "close_popover", %{"anchor" => "available-button-#{c.rent.id}-2026-10"})
      assert has_element?(view, ~s|#popover[data-show="true"]|)

      view |> element("#move-form button", "Abbrechen") |> render_click()
      refute has_element?(view, ~s|#popover[data-show="true"]|)
    end

    test "leads to the category's details", c do
      {:ok, view, _html} = open(c.conn)

      view |> element("#available-button-#{c.groceries.id}-2026-10") |> render_click()

      assert view |> element("#popover-details") |> render() =~
               ~s|&quot;focus&quot;,{&quot;to&quot;:&quot;#available-button-#{c.groceries.id}-2026-10&quot;}|

      view |> element("#popover-details") |> render_click()

      assert has_element?(view, ~s|dialog#category-dialog[data-show="true"]|, "🛒 Lebensmittel")
      refute has_element?(view, ~s|#popover[data-show="true"]|)
    end
  end

  describe "a category's dialog" do
    test "the name or the pencil opens the dialog: name, target, note and deleting", c do
      Categories.update_category(budget_scope(), c.groceries, %{note: "Wocheneinkauf"})
      spend(c, nil, -999)
      {:ok, view, _html} = open(c.conn)

      refute has_element?(view, ~s|dialog#category-dialog[data-show="true"]|)
      refute has_element?(view, "#edit-category-uncategorised")

      view |> element("#select-#{c.groceries.id}") |> render_click()

      assert has_element?(view, ~s|dialog#category-dialog[data-show="true"]|)
      assert has_element?(view, "#category-dialog-title", "🛒 Lebensmittel")
      assert has_element?(view, "#category-dialog", "Oktober 2026")
      assert has_element?(view, "#category-dialog", "aktueller Monat")
      assert has_element?(view, ~s|#category-name-input[value="🛒 Lebensmittel"]|)
      assert has_element?(view, "#inspector-target", "Kein Ziel")
      assert has_element?(view, "#inspector-note", "Wocheneinkauf")
      assert has_element?(view, "#category-delete #edit-delete", "Kategorie löschen")
      refute has_element?(view, "#inspector-available")
      refute has_element?(view, "#panel")
      assert view |> element("#category-dialog") |> render() =~ "deselect"

      sections =
        Regex.scan(~r/<section[^>]* id="([a-z-]+)"/, render(element(view, "#category-dialog")),
          capture: :all_but_first
        )

      assert List.flatten(sections) ==
               ~w(category-name inspector-target inspector-note category-delete)

      render_click(view, "deselect", %{})

      assert has_element?(view, ~s|dialog#category-dialog[data-show="false"]|)
      refute has_element?(view, "#category-name")

      view |> element("#edit-category-#{c.fuel.id}") |> render_click()

      assert has_element?(view, "#category-dialog-title", "⛽ Tanken")
    end

    test "the bar of a target by a date shows the whole amount", c do
      income(c, 100_000)
      by_date(c.rent, 120_000, ~D[2027-06-01])
      Categories.assign(budget_scope(), c.rent, @october, 8_000)
      {:ok, view, _html} = open(c.conn)

      view |> element("#edit-category-#{c.rent.id}") |> render_click()

      refute has_element?(view, "#target-form")
      assert has_element?(view, "#inspector-target", "1.200,00 € bis 1. Juni 2027 ansparen")
      assert has_element?(view, ~s|#target-status progress[value="7"]|)
      assert has_element?(view, "#target-status", "Noch 53,34 € nötig")
      assert has_element?(view, "#inspector-target", "80,00 von 1.200,00 €")
      assert has_element?(view, "#target-rest", "Weise noch 53,34 € zu")

      view |> element("#target-assign") |> render_click()

      assert assigned(c.rent, @october) == 13_334
      assert has_element?(view, "#target-status", "Im Plan")
      refute has_element?(view, "#target-rest")
    end

    test "sets a monthly target from the focus month on", c do
      {:ok, view, _html} = open(c.conn)

      view |> element("#edit-category-#{c.groceries.id}") |> render_click()
      view |> element("#target-edit") |> render_click()

      assert has_element?(view, ~s|dialog#category-dialog[data-show="true"] #target-form|)
      refute has_element?(view, "#target-delete")
      refute has_element?(view, "#target-due")

      view
      |> form("#target-form", %{
        "target" => %{"amount" => "700", "cadence" => "monthly", "set_aside" => "false"}
      })
      |> render_submit()

      assert %{cadence: :monthly, amount: 70_000, set_aside: false, from_month: @october} =
               Categories.target_for(budget_scope(), c.groceries, @october)

      assert has_element?(view, "#inspector-target", "Jeden Monat auffüllen bis 700,00 €")
      refute has_element?(view, "#inspector-target", "bis zum")
      assert has_element?(view, "#target-status", "Noch 700,00 € nötig")
      assert has_element?(view, "#flash-info", "Ziel gespeichert.")
    end

    test "edits a target by a date that repeats, and one that does not", c do
      {:ok, view, _html} = open(c.conn)

      view |> element("#edit-category-#{c.rent.id}") |> render_click()
      view |> element("#target-edit") |> render_click()

      view
      |> form("#target-form", %{"target" => %{"cadence" => "by_date"}})
      |> render_change()

      assert has_element?(view, "#target-due-on")
      assert has_element?(view, "#target-repeats")

      view
      |> form("#target-form", %{
        "target" => %{
          "amount" => "450",
          "cadence" => "by_date",
          "due_on" => "2026-12-24",
          "repeats_yearly" => "true"
        }
      })
      |> render_submit()

      assert %{cadence: :by_date, amount: 45_000, due_on: ~D[2026-12-24], repeats_yearly: true} =
               Categories.target_for(budget_scope(), c.rent, @october)

      assert has_element?(view, "#inspector-target", "450,00 € bis 24. Dezember ansparen")
      assert has_element?(view, "#inspector-target", "Jedes Jahr")

      view |> element("#target-edit") |> render_click()

      assert has_element?(view, ~s|#target-due-on[value="2026-12-24"]|)
      assert has_element?(view, "#target-repeats[checked]")

      view
      |> form("#target-form", %{
        "target" => %{"due_on" => "2027-03-01", "repeats_yearly" => "false"}
      })
      |> render_submit()

      assert %{due_on: ~D[2027-03-01], repeats_yearly: false} =
               Categories.target_for(budget_scope(), c.rent, @october)

      assert has_element?(view, "#inspector-target", "Einmalig")
    end

    test "edits a repeating target after its due date", c do
      {:ok, _} =
        Categories.set_target(budget_scope(), c.rent, %{
          from_month: ~D[2026-09-01],
          cadence: :by_date,
          amount: 30_000,
          due_on: ~D[2026-09-20],
          repeats_yearly: true
        })

      {:ok, view, _html} = open(c.conn)

      view |> element("#edit-category-#{c.rent.id}") |> render_click()
      view |> element("#target-edit") |> render_click()

      assert has_element?(view, ~s|#target-due-on[value="2027-09-20"]|)

      view |> form("#target-form", %{"target" => %{"amount" => "360"}}) |> render_submit()

      assert %{amount: 36_000, due_on: ~D[2027-09-20], repeats_yearly: true} =
               Categories.target_for(budget_scope(), c.rent, @october)
    end

    test "a target editor that is not filled in right says why and keeps what was typed", c do
      {:ok, view, _html} = open(c.conn)

      view |> element("#edit-category-#{c.rent.id}") |> render_click()
      view |> element("#target-edit") |> render_click()

      view
      |> form("#target-form", %{"target" => %{"amount" => "viel"}})
      |> render_submit()

      assert has_element?(view, ~s|#target-amount[aria-invalid=true][value="viel"]|)

      view
      |> form("#target-form", %{"target" => %{"cadence" => "by_date"}})
      |> render_change()

      view
      |> form("#target-form", %{
        "target" => %{"amount" => "300", "cadence" => "by_date", "due_on" => "2026-09-30"}
      })
      |> render_submit()

      assert has_element?(view, "#target-due-on-error-0", "Darf nicht vor dem Beginn")
      assert Categories.target_for(budget_scope(), c.rent, @october) == nil

      view |> element("#target-cancel") |> render_click()

      refute has_element?(view, "#target-form")
      assert has_element?(view, "#inspector-target", "Kein Ziel")
    end

    test "deletes a target from the focus month on", c do
      monthly(c.groceries, 40_000, ~D[2026-09-01])
      {:ok, view, _html} = open(c.conn)

      view |> element("#edit-category-#{c.groceries.id}") |> render_click()
      view |> element("#target-edit") |> render_click()
      Confirm.confirm_click(view, "#target-delete", "Ziel löschen?")

      assert Categories.target_for(budget_scope(), c.groceries, @october) == nil
      assert Categories.target_for(budget_scope(), c.groceries, ~D[2026-09-01]).amount == 40_000
      assert has_element?(view, "#inspector-target", "Kein Ziel")
    end

    test "snoozes the target in the focus month and resumes it", c do
      monthly(c.groceries, 40_000)
      {:ok, view, _html} = open(c.conn)

      view |> element("#edit-category-#{c.groceries.id}") |> render_click()
      view |> element("#target-snooze", "Pausieren") |> render_click()

      assert Categories.target_snoozed?(budget_scope(), c.groceries, @october)
      assert has_element?(view, "#inspector-target .badge", "pausiert")
      assert has_element?(view, "#inspector-target", "Im Oktober pausiert")

      view |> element("#target-snooze", "Fortsetzen") |> render_click()

      refute Categories.target_snoozed?(budget_scope(), c.groceries, @october)
      assert has_element?(view, "#target-status", "Noch 400,00 € nötig")
    end

    test "another focus month closes the target editor", c do
      {:ok, view, _html} = open(c.conn, months: 2)

      view |> element("#edit-category-#{c.groceries.id}") |> render_click()
      view |> element("#target-edit") |> render_click()
      assert has_element?(view, "#target-form")

      render_click(view, "focus", %{"month" => "2026-11"})

      refute has_element?(view, "#target-form")
      assert has_element?(view, "#category-dialog", "November 2026")
    end
  end

  describe "on phones" do
    test "a category opens in a sheet", c do
      {:ok, view, _html} = open(c.conn, compact: true)

      refute has_element?(view, "#category-dialog")
      refute has_element?(view, "#edit-category-#{c.groceries.id}")

      view |> element("#select-#{c.groceries.id}") |> render_click()

      assert has_element?(view, ~s|dialog#panel[data-show="true"]|, "🛒 Lebensmittel")

      sections =
        Regex.scan(~r/<section[^>]* id="([a-z-]+)"/, render(element(view, "#panel")),
          capture: :all_but_first
        )

      assert List.flatten(sections) ==
               ~w(inspector-available inspector-target inspector-auto category-name category-delete)

      assert has_element?(view, ~s|#panel form[method=dialog] button[aria-label="Schließen"]|)
      assert view |> element("#panel") |> render() =~ "deselect"

      render_click(view, "deselect", %{})

      assert has_element?(view, ~s|dialog#panel[data-show="false"]|)
      refute has_element?(view, "#panel", "🛒 Lebensmittel")
    end

    test "the sheet takes the assignment, which phones show nowhere else", c do
      {:ok, view, _html} = open(c.conn, compact: true)

      view |> element("#select-#{c.groceries.id}") |> render_click()
      assert has_element?(view, ~s|#panel-assign[value="0,00"]|)

      view |> form("#panel-assign-form", %{"value" => "75"}) |> render_submit()
      assert assigned(c.groceries, @october) == 7_500
      assert has_element?(view, ~s|#panel-assign[value="75,00"]|)

      view |> form("#panel-assign-form", %{"value" => "viel"}) |> render_submit()
      assert has_element?(view, ~s|#panel-assign[aria-invalid=true][value="viel"]|)
      assert assigned(c.groceries, @october) == 7_500
    end

    test "an overspent category has a hint to cover it", c do
      income(c, 10_000)
      spend(c, c.fuel, -2_500)
      {:ok, view, _html} = open(c.conn, compact: true)

      view |> element("#select-#{c.fuel.id}") |> render_click()
      view |> element("#cover-hint-#{c.fuel.id}") |> render_click()

      assert has_element?(view, "#panel #popover", "Überzug decken")

      view |> form("#cover-form") |> render_submit()

      assert assigned(c.fuel, @october) == 2_500
      refute has_element?(view, "#inspector-cover")
    end

    test "auto-assign works on the category alone, and its target in the sheet", c do
      income(c, 100_000)
      monthly(c.groceries, 40_000)
      monthly(c.rent, 50_000)
      {:ok, view, _html} = open(c.conn, compact: true)

      view |> element("#select-#{c.groceries.id}") |> render_click()

      assert has_element?(view, "#panel #inspector-target", "Jeden Monat")
      view |> element("#panel #auto-underfunded button") |> render_click()

      assert assigned(c.groceries, @october) == 40_000
      assert assigned(c.rent, @october) == 0
    end
  end

  defp open(conn, opts \\ []) do
    fit = %{
      "months" => Keyword.get(opts, :months, 1),
      "span" => 12,
      "compact" => Keyword.get(opts, :compact, false)
    }

    conn
    |> put_connect_params(%{"fit" => fit})
    |> live(Keyword.get(opts, :path, ~p"/budget"))
  end

  defp calculation(view, key) do
    html = render(element(view, "#calc-#{key}"))

    Enum.zip(
      Regex.scan(~r/<dt>([^<]+)<\/dt>/, html, capture: :all_but_first),
      Regex.scan(~r/<data[^>]* value="([-\d.]+)"/, html, capture: :all_but_first)
    )
    |> Enum.map(fn {[label], [value]} -> {label, value} end)
  end

  defp sum(lines),
    do: Enum.reduce(lines, Decimal.new(0), fn {_label, value}, sum -> Decimal.add(sum, value) end)

  defp ready(view, key) do
    [value] =
      Regex.run(~r/value="([-\d.]+)"/, render(element(view, "#ready-#{key}")),
        capture: :all_but_first
      )

    Decimal.new(value)
  end

  defp monthly(category, amount, from \\ @october) do
    {:ok, _} =
      Categories.set_target(budget_scope(), category, %{
        from_month: from,
        cadence: :monthly,
        amount: amount
      })
  end

  defp by_date(category, amount, due_on) do
    {:ok, _} =
      Categories.set_target(budget_scope(), category, %{
        from_month: @october,
        cadence: :by_date,
        amount: amount,
        due_on: due_on
      })
  end

  defp income(c, amount, date \\ @october) do
    {:ok, payee} =
      Ledger.create_payee(budget_scope(), %{name: "Arbeitgeber #{System.unique_integer()}"})

    transaction_fixture(
      account_id: c.checking.id,
      category_id: c.rta.id,
      payee_id: payee.id,
      amount: amount,
      date: date
    )
  end

  defp spend(c, category, amount, date \\ ~D[2026-10-05]) do
    transaction_fixture(
      account_id: c.checking.id,
      category_id: category && category.id,
      amount: amount,
      date: date
    )
  end

  defp assigned(category, month) do
    Map.get(Categories.budget(budget_scope()).assigned, {category.id, month}, 0)
  end
end
