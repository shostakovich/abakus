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
    test "its head adds up to Zu verteilen, last month's overspending and later months included",
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

      assert has_element?(view, ".app-heads-rta #calc-toggle-2026-10", "Zu verteilen")

      for key <- ~w(2026-09 2026-10 2026-11) do
        assert sum(calculation(view, key)) == ready(view, key)
      end

      assert ready(view, "2026-10") == Decimal.new("1075.00")
      refute has_element?(view, "#calc-2026-11", "Für spätere Monate")
      refute has_element?(view, "#calc-2026-09", "Für spätere Monate")

      assert has_element?(
               view,
               ".app-heads-rta #calc-toggle-2026-09",
               "Nicht verteilt am Monatsende"
             )
    end

    test "Unterfinanziert fills every target's share as far as Zu verteilen reaches", c do
      income(c, 60_000)
      monthly(c.groceries, 40_000)
      by_date(c.rent, 120_000, ~D[2027-06-01])
      {:ok, view, _html} = open(c.conn)

      assert has_element?(
               view,
               "#distribute-underfunded-2026-10",
               "533,34\u00A0€"
             )

      view |> element("#distribute-underfunded-2026-10") |> render_click()

      assert assigned(c.groceries, @october) == 40_000
      assert assigned(c.rent, @october) == 13_334
      assert toast(view, "Ziele mit 533,34 € gefüllt.")

      income(c, 50_000, @november)
      monthly(c.fuel, 50_000)

      {:ok, view, _html} = open(c.conn, months: 2)

      assert has_element?(
               view,
               "#distribute-underfunded-2026-11",
               "566,66\u00A0€"
             )

      view |> element("#distribute-underfunded-2026-11") |> render_click()

      assert assigned(c.groceries, @november) == 40_000
      assert assigned(c.fuel, @november) == 16_666
      assert assigned(c.rent, @november) == 0
      assert toast(view, "Ziele mit 566,66 € gefüllt.")
    end

    test "filling the underfunded can be undone", c do
      income(c, 60_000)
      monthly(c.groceries, 40_000)
      monthly(c.rent, 50_000)
      Categories.assign(budget_scope(), c.rent, @october, 10_000)
      {:ok, view, _html} = open(c.conn)

      view |> element("#distribute-underfunded-2026-10") |> render_click()

      assert assigned(c.groceries, @october) == 40_000
      assert assigned(c.rent, @october) == 20_000

      undo(view)

      assert assigned(c.groceries, @october) == 0
      assert assigned(c.rent, @october) == 10_000
      assert has_element?(view, "#ready-2026-10", "500,00\u00A0€")
      refute has_element?(view, "#flash-group button", "Rückgängig")
    end

    test "Verteilen › Zurücksetzen takes back what the month has assigned, after asking",
         c do
      Categories.assign(budget_scope(), c.groceries, @october, 10_000)
      Categories.assign(budget_scope(), c.rent, @october, 20_000)
      Categories.assign(budget_scope(), c.rent, @november, 20_000)
      {:ok, view, _html} = open(c.conn)

      assert menu_item(view, "underfunded", "2026-10", "Nichts unterfinanziert")
      assert has_element?(view, "#distribute-reset-2026-10", "Zuweisungen im Okt")

      Confirm.confirm_click(
        view,
        "#distribute-reset-2026-10",
        "Alle Zuweisungen im Oktober zurücksetzen?"
      )

      assert assigned(c.groceries, @october) == 0
      assert assigned(c.rent, @october) == 0
      assert assigned(c.rent, @november) == 20_000
      assert has_element?(view, "#flash-info", "Zuweisungen im Oktober zurückgesetzt.")
      assert menu_item(view, "reset", "2026-10", "Nichts zugewiesen")
    end

    test "Verteilen always shows; what cannot run is dimmed and says why", c do
      income(c, 5_000)
      {:ok, view, _html} = open(c.conn)

      assert has_element?(view, ~s|#distribute-2026-10 summary[aria-label="Verteilen"]|)
      assert menu_item(view, "underfunded", "2026-10", "Nichts unterfinanziert")
      assert menu_item(view, "reset", "2026-10", "Nichts zugewiesen")
      refute has_element?(view, "#distribute-underfunded-2026-10", "€")

      Categories.assign(budget_scope(), c.fuel, @october, 7_000)
      monthly(c.groceries, 10_000)
      {:ok, view, _html} = open(c.conn)

      assert has_element?(view, "#ready-2026-10", "−20,00")
      assert menu_item(view, "underfunded", "2026-10", "Nichts zu verteilen")
      assert has_element?(view, "#distribute-reset-2026-10:not([disabled])")
      assert has_element?(view, "#distribute-reset-2026-10.text-error-ink")
    end

    test "Zurücksetzen runs while any category has an assignment, even when they add up to zero",
         c do
      Categories.assign(budget_scope(), c.groceries, @october, 5_000)
      Categories.assign(budget_scope(), c.rent, @october, -5_000)
      {:ok, view, _html} = open(c.conn)

      assert has_element?(view, "#total-2026-10-assigned", "0,00")
      assert has_element?(view, "#distribute-reset-2026-10:not([disabled])")

      Confirm.confirm_click(
        view,
        "#distribute-reset-2026-10",
        "Alle Zuweisungen im Oktober zurücksetzen?"
      )

      assert assigned(c.groceries, @october) == 0
      assert assigned(c.rent, @october) == 0
      assert menu_item(view, "reset", "2026-10", "Nichts zugewiesen")
    end

    test "Ziele füllen names what it moves: at most what Zu verteilen holds", c do
      income(c, 3_000)
      monthly(c.rent, 50_000)
      {:ok, view, _html} = open(c.conn)

      assert has_element?(
               view,
               "#distribute-underfunded-2026-10:not([disabled])",
               "30,00\u00A0€"
             )

      view |> element("#distribute-underfunded-2026-10") |> render_click()

      assert assigned(c.rent, @october) == 3_000
      assert toast(view, "Ziele mit 30,00 € gefüllt.")
    end

    test "a closed month's Verteilen has nothing to do when later months assigned what it left",
         c do
      income(c, 5_000, ~D[2026-09-01])
      Categories.assign(budget_scope(), c.fuel, @october, 5_000)

      {:ok, view, _html} = live(c.conn, ~p"/budget?month=2026-09")

      assert has_element?(view, "#ready-2026-09", "50,00")
      assert menu_item(view, "underfunded", "2026-09", "Nichts unterfinanziert")
      assert menu_item(view, "reset", "2026-09", "Nichts zugewiesen")
    end

    test "Verteilen fills the underfunded only while money is unassigned", c do
      monthly(c.fuel, 12_000)
      {:ok, view, _html} = open(c.conn)

      assert menu_item(view, "underfunded", "2026-10", "Nichts zu verteilen")

      income(c, 5_000)
      {:ok, view, _html} = open(c.conn)

      view |> element("#distribute-underfunded-2026-10") |> render_click()

      assert assigned(c.fuel, @october) == 5_000
      assert has_element?(view, "#distribute-reset-2026-10:not([disabled])")
    end
  end

  describe "Verfügbar" do
    test "the ring shows the month's share of an underfunded target", c do
      income(c, 100_000)

      christmas =
        category_fixture(name: "🎄 Weihnachten", category_group_id: c.rent.category_group_id)

      {:ok, _} =
        Categories.set_target(budget_scope(), christmas, %{
          from_month: @november,
          cadence: :monthly,
          amount: 4_000,
          set_aside: true
        })

      Categories.assign(budget_scope(), christmas, @november, 2_500)
      {:ok, view, _html} = open(c.conn, months: 2)

      cell = "#available-#{christmas.id}-2026-11 .app-avail"

      assert has_element?(view, "#{cell}.text-warning-ink .sr-only", "62\u00A0% finanziert")

      assert has_element?(
               view,
               ~s|#{cell} svg.app-ring circle.app-ring-fill[stroke-dasharray="62 100"]|
             )

      refute has_element?(view, "#{cell} svg.lucide")

      view |> element("#month-2026-11") |> render_click()
      view |> element("#edit-category-#{christmas.id}") |> render_click()

      assert has_element?(view, "#target-status", "Noch 15,00 € im November")
    end

    test "only an overspent Verfügbar is a button", c do
      Categories.assign(budget_scope(), c.groceries, @october, 10_000)
      spend(c, c.fuel, -2_500)
      {:ok, view, _html} = open(c.conn)

      refute has_element?(view, "#available-button-#{c.groceries.id}-2026-10")
      refute has_element?(view, "#available-#{c.groceries.id}-2026-10 button")
      assert has_element?(view, "#available-#{c.groceries.id}-2026-10 .app-avail", "100,00")
      refute has_element?(view, "#available-button-#{c.rent.id}-2026-10")

      assert has_element?(
               view,
               ~s|#available-button-#{c.fuel.id}-2026-10.text-error-ink[aria-label*="überzogen"]|,
               "−25,00"
             )

      render_hook(view, "open_popover", %{"category" => "#{c.groceries.id}", "month" => "2026-10"})

      refute has_element?(view, "#popover")
    end

    test "covering takes as much as the source holds", c do
      Categories.assign(budget_scope(), c.groceries, @october, 2_000)
      Categories.assign(budget_scope(), c.rent, @october, 30_000)
      spend(c, c.fuel, -4_000)
      {:ok, view, _html} = open(c.conn)

      view |> element("#available-button-#{c.fuel.id}-2026-10") |> render_click()

      assert has_element?(
               view,
               ~s|#popover[data-show="true"][data-anchor="available-button-#{c.fuel.id}-2026-10"]|,
               "40,00\u00A0€ decken aus"
             )

      assert cover_sources(view) == [{"🏠", "Miete", "300.00"}, {"🛒", "Lebensmittel", "20.00"}]
      refute has_element?(view, "#popover input")
      refute has_element?(view, "#popover button[type=submit]")
      refute has_element?(view, "#category-dialog[data-show=true]")

      view |> element("#cover-from-#{c.groceries.id}") |> render_click()

      assert available(c.groceries) == 0
      assert available(c.fuel) == -2_000
      refute has_element?(view, ~s|#popover[data-show="true"]|)
      assert toast(view, "20,00 € aus Lebensmittel gedeckt.")

      view |> element("#available-button-#{c.fuel.id}-2026-10") |> render_click()

      assert has_element?(view, "#popover", "20,00\u00A0€ decken aus")
      assert cover_sources(view) == [{"🏠", "Miete", "300.00"}]

      view |> element("#cover-from-#{c.rent.id}") |> render_click()

      assert available(c.rent) == 28_000
      assert available(c.fuel) == 0
      refute has_element?(view, "#available-button-#{c.fuel.id}-2026-10")
    end

    test "covers from Zu verteilen first", c do
      income(c, 100_000)
      Categories.assign(budget_scope(), c.groceries, @october, 2_000)
      spend(c, c.fuel, -2_500)
      {:ok, view, _html} = open(c.conn)

      view |> element("#available-button-#{c.fuel.id}-2026-10") |> render_click()

      assert cover_sources(view) == [
               {"", "Zu verteilen", "980.00"},
               {"🛒", "Lebensmittel", "20.00"}
             ]

      assert has_element?(view, "#cover-from-rta[autofocus] svg.lucide")
      assert has_element?(view, "#cover-from-rta .text-success-ink", "980,00")
      refute has_element?(view, "#popover", "📥")

      view |> element("#cover-from-rta") |> render_click()

      assert assigned(c.fuel, @october) == 2_500
      assert has_element?(view, "#ready-2026-10", "955,00\u00A0€")
      assert toast(view, "25,00 € aus „Zu verteilen“ gedeckt.")
    end

    test "covering can be undone, which keeps what changed since", c do
      Categories.assign(budget_scope(), c.groceries, @october, 2_000)
      Categories.assign(budget_scope(), c.rent, @october, 30_000)
      spend(c, c.fuel, -4_000)
      {:ok, view, _html} = open(c.conn)

      view |> element("#available-button-#{c.fuel.id}-2026-10") |> render_click()
      view |> element("#cover-from-#{c.rent.id}") |> render_click()

      assert assigned(c.rent, @october) == 26_000
      assert assigned(c.fuel, @october) == 4_000

      undo(view)

      assert assigned(c.rent, @october) == 30_000
      assert assigned(c.fuel, @october) == 0
      assert has_element?(view, "#available-button-#{c.fuel.id}-2026-10", "−40,00")

      view |> element("#available-button-#{c.fuel.id}-2026-10") |> render_click()
      view |> element("#cover-from-#{c.rent.id}") |> render_click()
      Categories.assign(budget_scope(), c.rent, @october, 25_000)

      undo(view)

      assert assigned(c.rent, @october) == 29_000
      assert assigned(c.fuel, @october) == 0

      render_click(view, "undo", %{"id" => "stale"})
      render_click(view, "undo", %{})

      assert assigned(c.rent, @october) == 29_000
      assert assigned(c.fuel, @october) == 0
    end

    test "renaming, sorting and deleting end the offer to undo", c do
      income(c, 10_000)
      for category <- [c.groceries, c.fuel, c.rent], do: spend(c, category, -1_000)
      empty = category_group_fixture(name: "Leer", position: 2)
      {:ok, view, _html} = open(c.conn)

      actions = [
        {c.groceries,
         fn ->
           view |> element("#select-#{c.rent.id}") |> render_click()
           render_hook(view, "edit_save", %{"name" => "🏠 Wohnung"})
         end},
        {c.fuel,
         fn ->
           render_hook(view, "sort_category", %{
             "id" => c.rent.id,
             "section" => c.groceries.category_group_id,
             "index" => 0
           })
         end},
        {c.rent, fn -> render_click(view, "delete_group", %{"group" => empty.id}) end}
      ]

      for {category, action} <- actions do
        render_click(view, "cover", %{"category" => category.id, "from" => "rta"})
        assert toast(view, "10,00 € aus „Zu verteilen“ gedeckt.")

        [id] =
          Regex.run(~r/&quot;id&quot;:&quot;(\d+)&quot;/, render(element(view, "#flash-group")),
            capture: :all_but_first
          )

        action.()

        refute toast(view, "gedeckt.")
        render_click(view, "undo", %{"id" => id})
        assert assigned(category, @october) == 1_000
      end
    end

    test "offers only what has money", c do
      income(c, 10_000)
      Categories.assign(budget_scope(), c.groceries, @october, 10_000)
      spend(c, c.fuel, -2_500)
      {:ok, view, _html} = open(c.conn)

      view |> element("#available-button-#{c.fuel.id}-2026-10") |> render_click()

      assert has_element?(view, "#ready-2026-10", "0,00\u00A0€")
      assert cover_sources(view) == [{"🛒", "Lebensmittel", "100.00"}]
      refute has_element?(view, "#cover-from-rta")
      refute has_element?(view, "#cover-from-#{c.rent.id}")

      spend(c, c.groceries, -10_000)
      {:ok, view, _html} = open(c.conn)

      view |> element("#available-button-#{c.fuel.id}-2026-10") |> render_click()

      assert has_element?(
               view,
               "#popover #cover-sources .setzkasten-pick-empty",
               "Kein Geld in „Zu verteilen“ oder anderen Kategorien."
             )

      assert cover_sources(view) == []
    end

    test "covers nothing from itself, Ready to Assign as a category or ids it cannot read", c do
      hidden = Categories.ready_to_assign!(budget_scope())
      Categories.assign(budget_scope(), c.groceries, @october, 10_000)
      spend(c, c.fuel, -2_500)
      {:ok, view, _html} = open(c.conn)

      fuel = "#{c.fuel.id}"

      for from <- ["#{hidden.id}", fuel, %{"a" => "1"}, "#{c.rent.id}"] do
        render_hook(view, "cover", %{"category" => fuel, "from" => from})
      end

      render_hook(view, "cover", %{"category" => "#{c.groceries.id}", "from" => "rta"})
      render_hook(view, "cover", %{"category" => %{}, "from" => "rta"})

      assert assigned(hidden, @october) == 0
      assert assigned(c.groceries, @october) == 10_000
      assert assigned(c.fuel, @october) == 0
      assert has_element?(view, "#flash-error", "Daraus lässt sich nichts decken.")
    end

    test "closes on cancel, and a click away closes only its own popover", c do
      spend(c, c.fuel, -2_500)
      {:ok, view, _html} = open(c.conn)

      view |> element("#available-button-#{c.fuel.id}-2026-10") |> render_click()
      render_hook(view, "close_popover", %{"anchor" => "available-button-#{c.rent.id}-2026-10"})
      assert has_element?(view, ~s|#popover[data-show="true"]|)

      render_hook(view, "close_popover", %{"anchor" => "available-button-#{c.fuel.id}-2026-10"})
      refute has_element?(view, ~s|#popover[data-show="true"]|)
    end
  end

  describe "a category's dialog" do
    test "the name or the pencil opens the dialog: name, target and deleting", c do
      spend(c, nil, -999)
      {:ok, view, _html} = open(c.conn)

      refute has_element?(view, ~s|dialog#category-dialog[data-show="true"]|)
      refute has_element?(view, "#edit-category-uncategorised")

      view |> element("#select-#{c.groceries.id}") |> render_click()

      assert has_element?(view, ~s|dialog#category-dialog[data-show="true"]|)
      assert has_element?(view, ~s|#category-dialog[aria-labelledby="category-dialog-title"]|)
      refute has_element?(view, "#category-dialog h2")

      assert has_element?(
               view,
               ~s|#category-dialog .setzkasten-modal-head #category-dialog-title[value="🛒 Lebensmittel"]|
             )

      refute has_element?(view, "#category-dialog h3", "Name")
      assert has_element?(view, "#category-head", "Oktober 2026")
      assert has_element?(view, "#category-head", "aktueller Monat")
      assert has_element?(view, "#inspector-target", "Kein Ziel")
      assert has_element?(view, "#category-delete #edit-delete", "Kategorie löschen")
      refute has_element?(view, "#inspector-available")
      refute has_element?(view, "#panel")
      assert view |> element("#category-dialog") |> render() =~ "deselect"

      sections =
        Regex.scan(~r/<section[^>]* id="([a-z-]+)"/, render(element(view, "#category-dialog")),
          capture: :all_but_first
        )

      assert List.flatten(sections) == ~w(inspector-target category-delete)

      render_click(view, "deselect", %{})

      assert has_element?(view, ~s|dialog#category-dialog[data-show="false"]|)
      refute has_element?(view, "#category-dialog-title")

      view |> element("#edit-category-#{c.fuel.id}") |> render_click()

      assert has_element?(view, ~s|#category-dialog-title[value="⛽ Tanken"]|)
    end

    test "the bar of a target by a date shows the whole amount", c do
      income(c, 100_000)
      by_date(c.rent, 120_000, ~D[2027-06-01])
      Categories.assign(budget_scope(), c.rent, @october, 8_000)
      {:ok, view, _html} = open(c.conn)

      view |> element("#edit-category-#{c.rent.id}") |> render_click()

      refute has_element?(view, "#target-form")

      assert has_element?(
               view,
               "#target-head",
               "Bis zum 1. Juni 2027 weitere 1.200,00\u00A0€ zurücklegen"
             )

      assert has_element?(
               view,
               ~s|#target-progress progress.progress-warning[value="7"][aria-label="80,00 von 1.200,00\u00A0€ zurückgelegt"]|
             )

      assert has_element?(view, ~s|#target-progress svg rect[x="11%"]|)
      assert has_element?(view, "#target-saved", "80,00 von 1.200,00\u00A0€ zurückgelegt")
      refute has_element?(view, "#inspector-target", "%")

      assert has_element?(
               view,
               "#target-status.text-warning-ink",
               "Noch 53,34\u00A0€ im Oktober"
             )

      assert has_element?(view, "#target-assign", "53,34\u00A0€ zuweisen")
      refute has_element?(view, "#target-assign[aria-label]")

      view |> element("#target-assign") |> render_click()

      assert assigned(c.rent, @october) == 13_334
      assert has_element?(view, "#target-status", "Im Plan")
      assert has_element?(view, "#target-progress progress.progress-success")
      refute has_element?(view, "#target-assign")
    end

    test "a funded target by a date that saves up says what it has angespart, its bar green", c do
      income(c, 200_000)
      by_date(c.rent, 120_000, ~D[2027-06-01], false)
      Categories.assign(budget_scope(), c.rent, @october, 120_000)
      {:ok, view, _html} = open(c.conn)

      view |> element("#edit-category-#{c.rent.id}") |> render_click()

      assert has_element?(
               view,
               "#target-head",
               "Bis zum 1. Juni 2027 auf 1.200,00\u00A0€ ansparen"
             )

      assert has_element?(view, ~s|#target-progress progress.progress-success[value="100"]|)
      assert has_element?(view, "#target-saved", "1.200,00 von 1.200,00\u00A0€ angespart")
      assert has_element?(view, "#target-status.text-success-ink", "Erfüllt")
      refute has_element?(view, "#inspector-target", "%")
    end

    test "an overspent target by a date turns its bar red", c do
      income(c, 200_000)
      by_date(c.rent, 120_000, ~D[2027-06-01])
      Categories.assign(budget_scope(), c.rent, @october, 20_000)
      spend(c, c.rent, -21_200)
      {:ok, view, _html} = open(c.conn)

      view |> element("#edit-category-#{c.rent.id}") |> render_click()

      assert has_element?(view, "#target-progress progress.progress-error")

      assert has_element?(
               view,
               "#target-saved",
               ~r/^\s*200,00 von 1\.200,00\x{00A0}€ zurückgelegt\s*$/u
             )

      assert has_element?(view, "#target-status.text-error-ink", "Überzogen um 12,00\u00A0€")
    end

    test "a snoozed target by a date mutes its bar", c do
      by_date(c.rent, 120_000, ~D[2027-06-01])
      {:ok, view, _html} = open(c.conn)

      view |> element("#edit-category-#{c.rent.id}") |> render_click()
      view |> element("#target-snooze", "Pausieren") |> render_click()

      assert has_element?(view, "#target-progress progress.setzkasten-progress-neutral")
      assert has_element?(view, "#target-saved", "0,00 von 1.200,00\u00A0€ zurückgelegt")
      assert has_element?(view, "#target-status", "Pausiert im Oktober")
    end

    test "Zuweisen takes at most what Zu verteilen holds", c do
      income(c, 3_000)
      monthly(c.rent, 50_000)
      {:ok, view, _html} = open(c.conn)

      view |> element("#edit-category-#{c.rent.id}") |> render_click()

      assert has_element?(view, "#target-status", "Noch 500,00 € im Oktober")
      assert has_element?(view, "#target-assign", "30,00\u00A0€ zuweisen")

      view |> element("#target-assign") |> render_click()

      assert assigned(c.rent, @october) == 3_000
      assert toast(view, "30,00 € Miete zugewiesen.")
      assert has_element?(view, "#ready-2026-10", "0,00 €")
      assert has_element?(view, "#target-status", "Noch 470,00 € im Oktober")
      refute has_element?(view, "#target-assign")

      render_click(view, "assign_rest", %{})
      assert assigned(c.rent, @october) == 3_000
    end

    test "the target's Zuweisen can be undone", c do
      income(c, 50_000)
      monthly(c.rent, 20_000)
      Categories.assign(budget_scope(), c.rent, @october, 5_000)
      {:ok, view, _html} = open(c.conn)

      view |> element("#edit-category-#{c.rent.id}") |> render_click()
      view |> element("#target-assign", "150,00\u00A0€ zuweisen") |> render_click()

      assert assigned(c.rent, @october) == 20_000

      undo(view)

      assert assigned(c.rent, @october) == 5_000
      assert has_element?(view, "#target-assign", "150,00\u00A0€ zuweisen")
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

      assert has_element?(view, "#inspector-target", "Jeden Monat auffüllen bis 700,00\u00A0€")
      refute has_element?(view, "#inspector-target", "bis zum")
      assert has_element?(view, "#target-status", "Noch 700,00\u00A0€ im Oktober")
      refute has_element?(view, "#target-progress")
      refute has_element?(view, "#target-saved")
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

      assert has_element?(
               view,
               "#target-head",
               "Jedes Jahr bis zum 24. Dezember weitere 450,00\u00A0€ zurücklegen"
             )

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

      assert has_element?(view, "#target-head", "Bis zum 1. März 2027 weitere")
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
      assert has_element?(view, "#target-status", "Pausiert im Oktober")
      assert has_element?(view, "#available-#{c.groceries.id}-2026-10 .app-avail .lucide")
      refute has_element?(view, "#target-assign")

      view |> element("#target-snooze", "Fortsetzen") |> render_click()

      refute Categories.target_snoozed?(budget_scope(), c.groceries, @october)
      assert has_element?(view, "#target-status", "Noch 400,00\u00A0€ im Oktober")
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

      assert has_element?(
               view,
               ~s|dialog#panel[data-show="true"][aria-labelledby="panel-title"] #panel-title[value="🛒 Lebensmittel"]|
             )

      sections =
        Regex.scan(~r/<section[^>]* id="([a-z-]+)"/, render(element(view, "#panel")),
          capture: :all_but_first
        )

      assert List.flatten(sections) ==
               ~w(inspector-available inspector-target category-delete)

      assert has_element?(
               view,
               ~s|#panel .setzkasten-modal-head #panel-title[value="🛒 Lebensmittel"]|
             )

      refute has_element?(view, "#panel h3", "Name")

      assert has_element?(view, ~s|#panel form[method=dialog] button[aria-label="Schließen"]|)
      assert view |> element("#panel") |> render() =~ "deselect"

      render_click(view, "deselect", %{})

      assert has_element?(view, ~s|dialog#panel[data-show="false"]|)
      refute has_element?(view, "#panel #panel-title")
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

    test "the sheet's Zugewiesen adds and subtracts; another operator is refused inline", c do
      {:ok, view, _html} = open(c.conn, compact: true)

      view |> element("#select-#{c.groceries.id}") |> render_click()

      assert has_element?(view, ~s|#panel-assign[inputmode="text"]|)

      view |> form("#panel-assign-form", %{"value" => "50+20"}) |> render_submit()

      assert assigned(c.groceries, @october) == 7_000
      assert has_element?(view, ~s|#panel-assign[value="70,00"]|)

      view |> form("#panel-assign-form", %{"value" => "60*2"}) |> render_submit()

      assert has_element?(
               view,
               ~s|#panel-assign[aria-invalid=true][value="60*2"][aria-describedby="panel-assign-error-0"]|
             )

      assert has_element?(
               view,
               "#panel-assign-error-0",
               "„60*2“ ist kein gültiger Betrag. Rechnen geht mit +\u00A0und\u00A0−, etwa\u00A050+20."
             )

      assert_push_event(view, "refocus_amount", %{id: "panel-assign"})
      assert assigned(c.groceries, @october) == 7_000
      assert has_element?(view, ~s|#panel-assign[data-saved="70,00"]|)

      view
      |> element("#budget")
      |> render_hook("assign_cancel", %{"category" => c.groceries.id, "month" => "2026-10"})

      assert has_element?(view, ~s|#panel-assign[value="70,00"]:not([aria-invalid])|)
      refute has_element?(view, "#panel-assign-error-0")
    end

    test "the sheet says when an amount is too large, not how to add and subtract", c do
      {:ok, view, _html} = open(c.conn, compact: true)

      view |> element("#select-#{c.groceries.id}") |> render_click()
      view |> form("#panel-assign-form", %{"value" => "1.000.000.000.000"}) |> render_submit()

      assert has_element?(view, ~s|#panel-assign[aria-invalid=true][value="1.000.000.000.000"]|)

      assert has_element?(
               view,
               "#panel-assign-error-0",
               "Der Betrag muss zwischen -100.000.000.000 € und 100.000.000.000 € liegen."
             )

      refute has_element?(view, "#panel-assign-error-0", "Rechnen")
      assert assigned(c.groceries, @october) == 0
    end

    test "a tap on an overspent Verfügbar opens the list to cover from on its own", c do
      income(c, 10_000)
      Categories.assign(budget_scope(), c.groceries, @october, 1_000)
      spend(c, c.fuel, -2_500)
      {:ok, view, _html} = open(c.conn, compact: true)

      view |> element("#select-#{c.fuel.id}") |> render_click()

      refute has_element?(view, "#inspector-cover")
      refute has_element?(view, "#panel #popover")
      refute has_element?(view, "#panel", "Decken")

      render_click(view, "deselect", %{})
      view |> element("#available-button-#{c.fuel.id}-2026-10") |> render_click()

      assert has_element?(view, ~s|#popover[data-show="true"]|, "25,00\u00A0€ decken aus")
      refute has_element?(view, ~s|dialog#panel[data-show="true"]|)

      assert cover_sources(view) == [
               {"", "Zu verteilen", "90.00"},
               {"🛒", "Lebensmittel", "10.00"}
             ]

      view |> element("#cover-from-#{c.groceries.id}") |> render_click()

      assert available(c.groceries) == 0
      assert available(c.fuel) == -1_500
      refute has_element?(view, ~s|#popover[data-show="true"]|)
      assert toast(view, "10,00 € aus Lebensmittel gedeckt.")

      view |> element("#available-button-#{c.fuel.id}-2026-10") |> render_click()
      assert has_element?(view, "#popover", "15,00\u00A0€ decken aus")
      view |> element("#cover-from-rta") |> render_click()

      assert available(c.fuel) == 0
      refute has_element?(view, "#available-button-#{c.fuel.id}-2026-10")
    end

    test "the sheet's Zuweisen fills the category's target alone, as far as Zu verteilen reaches",
         c do
      income(c, 30_000)
      monthly(c.groceries, 40_000)
      monthly(c.rent, 50_000)
      {:ok, view, _html} = open(c.conn, compact: true)

      view |> element("#select-#{c.groceries.id}") |> render_click()

      refute has_element?(view, "#inspector-auto")
      assert has_element?(view, "#panel #inspector-target", "Jeden Monat")
      view |> element("#panel #target-assign") |> render_click()

      assert assigned(c.groceries, @october) == 30_000
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
    view
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.query("#calc-#{key} > div")
    |> Enum.map(fn line ->
      [value] = line |> LazyHTML.query("data") |> LazyHTML.attribute("value")
      {line |> LazyHTML.query("dt") |> LazyHTML.text(), value}
    end)
  end

  defp cover_sources(view) do
    view
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.query("#popover #cover-sources button[id^='cover-from-']")
    |> Enum.map(fn row ->
      [value | _shown_twice] = row |> LazyHTML.query("data") |> LazyHTML.attribute("value")
      text = &(row |> LazyHTML.query(&1) |> LazyHTML.text() |> String.trim())
      {text.(".setzkasten-pick-leading"), text.(".setzkasten-pick-label"), value}
    end)
  end

  defp toast(view, message) do
    view
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.query("#flash-group [role=status]")
    |> Enum.any?(fn toast ->
      text = toast |> LazyHTML.text() |> String.replace("\u00A0", " ")
      text =~ message and text =~ "Rückgängig"
    end)
  end

  defp undo(view), do: view |> element("#flash-group button", "Rückgängig") |> render_click()

  defp menu_item(view, kind, key, reason) do
    has_element?(view, "#distribute-#{kind}-#{key}[disabled]", reason) and
      has_element?(view, "li.menu-disabled #distribute-#{kind}-#{key}")
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

  defp by_date(category, amount, due_on, set_aside \\ true) do
    {:ok, _} =
      Categories.set_target(budget_scope(), category, %{
        from_month: @october,
        cadence: :by_date,
        amount: amount,
        due_on: due_on,
        set_aside: set_aside
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

  defp available(category) do
    Categories.budget(budget_scope())
    |> Abakus.Budget.months(@october, @october)
    |> Enum.find(&(&1.month == @october))
    |> Map.fetch!(:categories)
    |> Enum.find(&(&1.category_id == category.id))
    |> Map.fetch!(:available)
  end

  defp assigned(category, month) do
    Map.get(Categories.budget(budget_scope()).assigned, {category.id, month}, 0)
  end
end
