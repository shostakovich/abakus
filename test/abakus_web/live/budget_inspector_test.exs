defmodule AbakusWeb.BudgetInspectorTest do
  use AbakusWeb.ConnCase

  import Phoenix.LiveViewTest
  import Abakus.DomainFixtures

  alias Abakus.{Categories, Ledger}

  @october ~D[2026-10-01]
  @november ~D[2026-11-01]

  setup :register_and_log_in_user

  setup do
    checking = account_fixture(kind: :checking)
    rta = Categories.ready_to_assign!()
    daily = category_group_fixture(name: "🛒 Alltag", position: 0)
    housing = category_group_fixture(name: "🏠 Wohnen", position: 1)

    groceries =
      category_fixture(name: "🛒 Lebensmittel", category_group_id: daily.id, position: 0)

    fuel = category_fixture(name: "⛽ Tanken", category_group_id: daily.id, position: 1)
    rent = category_fixture(name: "🏠 Miete", category_group_id: housing.id)

    %{checking: checking, rta: rta, groceries: groceries, fuel: fuel, rent: rent}
  end

  describe "with nothing selected" do
    test "the inspector shows the month: overspent categories, auto-assign and later months", c do
      income(c, 100_000)
      Categories.assign(c.groceries, @october, 10_000)
      spend(c, c.fuel, -2_500)
      spend(c, nil, -999)
      Categories.assign(c.rent, @november, 30_000)
      monthly(c.rent, 50_000)

      {:ok, view, _html} = open(c.conn)

      assert has_element?(view, "#inspector h2", "Oktober 2026")
      assert has_element?(view, "#inspector-overspent .card-header", "2 überzogen")
      assert has_element?(view, "#overspent-#{c.fuel.id}", "−25,00 €")
      assert has_element?(view, "#overspent-#{c.fuel.id} button", "Decken")
      assert has_element?(view, ~s|#overspent-uncategorised a[href="/accounts/all"]|, "Zuordnen")
      assert has_element?(view, "#auto-underfunded", "500,00 €")
      assert has_element?(view, "#auto-reset", "100,00 €")
      assert has_element?(view, "#inspector-future", "300,00 €")
      assert has_element?(view, "#inspector-future", "November 2026")
    end

    test "covers an overspent category from Zu verteilen", c do
      income(c, 100_000)
      spend(c, c.fuel, -2_500)
      {:ok, view, _html} = open(c.conn)

      view |> element("#cover-#{c.fuel.id}") |> render_click()

      assert has_element?(view, "#popover", "Überzug decken · ⛽ Tanken")
      assert has_element?(view, "#cover-from option[value=rta]", "Zu verteilen (1.000,00 €)")

      view |> form("#cover-form", %{"from" => "rta"}) |> render_submit()

      assert assigned(c.fuel, @october) == 2_500
      refute has_element?(view, "#popover")
      refute has_element?(view, "#inspector-overspent")
      assert has_element?(view, "#flash-info", "25,00 € aus „Zu verteilen“ gedeckt.")
    end

    test "Unterfinanziert fills every target's share as far as Zu verteilen reaches", c do
      income(c, 60_000)
      monthly(c.groceries, 40_000)
      by_date(c.rent, 120_000, ~D[2027-06-01])
      {:ok, view, _html} = open(c.conn)

      view |> element("#auto-underfunded") |> render_click()

      assert assigned(c.groceries, @october) == 40_000
      assert assigned(c.rent, @october) == 13_334
      assert has_element?(view, "#flash-info", "Unterfinanzierte Ziele gefüllt.")

      income(c, 50_000, @november)
      monthly(c.fuel, 50_000)

      {:ok, view, _html} = open(c.conn, months: 2)
      view |> element("#month-2026-11") |> render_click()
      view |> element("#auto-underfunded") |> render_click()

      assert assigned(c.groceries, @november) == 40_000
      assert assigned(c.fuel, @november) == 16_666
      assert assigned(c.rent, @november) == 0
      assert has_element?(view, "#flash-info", "Nur teilweise gefüllt")
    end

    test "Zuweisung zurücksetzen takes back what the month has assigned", c do
      Categories.assign(c.groceries, @october, 10_000)
      Categories.assign(c.rent, @october, 20_000)
      Categories.assign(c.rent, @november, 20_000)
      {:ok, view, _html} = open(c.conn)

      view |> element("#auto-reset") |> render_click()

      assert assigned(c.groceries, @october) == 0
      assert assigned(c.rent, @october) == 0
      assert assigned(c.rent, @november) == 20_000
      assert has_element?(view, "#auto-reset[disabled]")
    end

    test "Verteilen › In eine Kategorie … assigns Zu verteilen to the category picked", c do
      income(c, 100_000)
      monthly(c.fuel, 12_000)
      {:ok, view, _html} = open(c.conn)

      view |> element("#distribute-pick-2026-10") |> render_click()

      assert has_element?(view, "#popover", "In eine Kategorie verteilen · Oktober")
      assert has_element?(view, ~s|#pick-category option[value="#{c.fuel.id}"][selected]|)
      assert has_element?(view, ~s|#pick-amount[value="120,00"]|)

      view
      |> form("#pick-form")
      |> render_change(%{"_target" => ["category"], "category" => "#{c.rent.id}"})

      assert has_element?(view, ~s|#pick-amount[value="1.000,00"]|)

      view
      |> form("#pick-form", %{"category" => "#{c.rent.id}", "amount" => "250"})
      |> render_submit()

      assert assigned(c.rent, @october) == 25_000
      assert has_element?(view, "#flash-info", "250,00 € an 🏠 Miete verteilt.")
      assert has_element?(view, "#ready-2026-10", "750,00 €")
    end

    test "Verteilen offers to fill the underfunded only while money is unassigned", c do
      monthly(c.fuel, 12_000)
      {:ok, view, _html} = open(c.conn)

      refute has_element?(view, "#distribute-toggle-2026-10")

      income(c, 5_000)
      {:ok, view, _html} = open(c.conn)

      view |> element("#distribute-underfunded-2026-10") |> render_click()

      assert assigned(c.fuel, @october) == 5_000
    end
  end

  describe "the available pill" do
    test "moves money to another category or to Zu verteilen", c do
      Categories.assign(c.groceries, @october, 10_000)
      {:ok, view, _html} = open(c.conn)

      view |> element("#pill-#{c.groceries.id}-2026-10") |> render_click()

      assert has_element?(view, "#popover", "🛒 Lebensmittel")
      refute has_element?(view, "#popover-cover")
      assert has_element?(view, ~s|#move-amount[value="100,00"]|)
      assert has_element?(view, "#move-to[checked]")

      view
      |> form("#move-form", %{"amount" => "30", "direction" => "to", "other" => "#{c.rent.id}"})
      |> render_submit()

      assert assigned(c.groceries, @october) == 7_000
      assert assigned(c.rent, @october) == 3_000

      assert has_element?(
               view,
               "#flash-info",
               "30,00 € von 🛒 Lebensmittel nach 🏠 Miete verschoben."
             )

      view |> element("#pill-#{c.rent.id}-2026-10") |> render_click()

      view
      |> form("#move-form", %{"amount" => "10", "direction" => "from", "other" => "rta"})
      |> render_submit()

      assert assigned(c.rent, @october) == 4_000
    end

    test "refuses hidden categories and ids it cannot read", c do
      hidden = category_fixture(name: "🙈 Versteckt", hidden: true)
      Categories.assign(c.groceries, @october, 10_000)
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
      Categories.assign(c.groceries, @october, 10_000)
      {:ok, view, _html} = open(c.conn)

      view |> element("#pill-#{c.groceries.id}-2026-10") |> render_click()

      view
      |> form("#move-form", %{"amount" => "viel", "direction" => "to", "other" => "rta"})
      |> render_submit()

      assert has_element?(view, "#popover .invalid-feedback", "Betrag")
      assert assigned(c.groceries, @october) == 10_000
    end

    test "covers overspending from another category, as far as it has", c do
      Categories.assign(c.groceries, @october, 1_000)
      spend(c, c.fuel, -2_500)
      {:ok, view, _html} = open(c.conn)

      view |> element("#pill-#{c.fuel.id}-2026-10") |> render_click()

      assert has_element?(view, "#popover-cover.active")
      refute has_element?(view, "#cover-from option[value=rta]")

      view |> form("#cover-form", %{"from" => "#{c.groceries.id}"}) |> render_submit()

      assert assigned(c.groceries, @october) == 0
      assert assigned(c.fuel, @october) == 1_000

      view |> element("#pill-#{c.fuel.id}-2026-10") |> render_click()
      view |> element("#popover-move") |> render_click()

      assert has_element?(view, "#move-form")
      assert has_element?(view, "#move-from[checked]")
    end

    test "closes on cancel, and a click away closes only its own popover", c do
      {:ok, view, _html} = open(c.conn)

      view |> element("#pill-#{c.groceries.id}-2026-10") |> render_click()
      render_hook(view, "close_popover", %{"anchor" => "pill-#{c.rent.id}-2026-10"})
      assert has_element?(view, "#popover")

      view |> element("#move-form button", "Abbrechen") |> render_click()
      refute has_element?(view, "#popover")
    end

    test "leads to the category's details", c do
      {:ok, view, _html} = open(c.conn)

      view |> element("#pill-#{c.groceries.id}-2026-10") |> render_click()
      view |> element("#popover-details") |> render_click()

      assert has_element?(view, "#inspector-name", "🛒 Lebensmittel")
      refute has_element?(view, "#popover")
    end
  end

  describe "with a category selected" do
    test "the inspector shows what is available and how, and the note", c do
      Categories.update_category(c.groceries, %{note: "Wocheneinkauf"})
      Categories.assign(c.groceries, ~D[2026-09-01], 5_000)
      spend(c, c.groceries, -7_000, ~D[2026-09-10])
      Categories.assign(c.groceries, @october, 20_000)
      spend(c, c.groceries, -4_000)
      {:ok, view, _html} = open(c.conn)

      view |> element("#select-#{c.groceries.id}") |> render_click()

      assert has_element?(view, "#category-#{c.groceries.id}.is-sel")
      assert has_element?(view, "#inspector-name", "🛒 Lebensmittel")
      assert has_element?(view, "#inspector", "Oktober 2026 · aktueller Monat")
      assert has_element?(view, "#inspector-available .app-pill", "160,00 €")
      assert has_element?(view, "#inspector-available", "Überzug im Sep")
      assert has_element?(view, "#inspector-available", "−20,00 €")
      assert has_element?(view, "#inspector-note", "Wocheneinkauf")
      assert has_element?(view, "#inspector-target", "Kein Ziel")

      view |> element("#inspector-back") |> render_click()

      assert has_element?(view, "#inspector h2", "Oktober 2026")
      refute has_element?(view, "#category-#{c.groceries.id}.is-sel")
    end

    test "an overspent category has a hint to cover it", c do
      income(c, 10_000)
      spend(c, c.fuel, -2_500)
      {:ok, view, _html} = open(c.conn)

      view |> element("#select-#{c.fuel.id}") |> render_click()
      view |> element("#cover-hint-#{c.fuel.id}") |> render_click()
      view |> form("#cover-form", %{"from" => "rta"}) |> render_submit()

      assert assigned(c.fuel, @october) == 2_500
      refute has_element?(view, "#inspector-cover")
    end

    test "the bar of a target by a date shows the whole amount", c do
      income(c, 100_000)
      by_date(c.rent, 120_000, ~D[2027-06-01])
      Categories.assign(c.rent, @october, 8_000)
      {:ok, view, _html} = open(c.conn)

      view |> element("#select-#{c.rent.id}") |> render_click()

      assert has_element?(view, "#inspector-target", "1.200,00 € bis 1. Juni 2027 ansparen")
      assert has_element?(view, "#target-status .progress-bar.app-w-7")
      assert has_element?(view, "#target-status", "Noch 53,34 € nötig")
      assert has_element?(view, "#inspector-target", "80,00 von 1.200,00 €")
      assert has_element?(view, "#target-rest", "Weise noch 53,34 € zu")

      view |> element("#target-assign") |> render_click()

      assert assigned(c.rent, @october) == 13_334
      assert has_element?(view, "#target-status", "Im Plan")
      refute has_element?(view, "#target-rest")
    end

    test "edits a monthly target from the focus month on", c do
      {:ok, view, _html} = open(c.conn)

      view |> element("#select-#{c.groceries.id}") |> render_click()
      view |> element("#target-edit") |> render_click()

      refute has_element?(view, "#target-delete")
      refute has_element?(view, "#target-due")

      view
      |> form("#target-form", %{
        "target" => %{"amount" => "700", "cadence" => "monthly", "set_aside" => "false"}
      })
      |> render_submit()

      assert %{cadence: :monthly, amount: 70_000, set_aside: false, from_month: @october} =
               Categories.target_for(c.groceries, @october)

      assert has_element?(view, "#inspector-target", "Jeden Monat auffüllen bis 700,00 €")
      refute has_element?(view, "#inspector-target", "bis zum")
      assert has_element?(view, "#target-status", "Noch 700,00 € nötig")
      assert has_element?(view, "#flash-info", "Ziel gespeichert.")
    end

    test "edits a target by a date that repeats, and one that does not", c do
      {:ok, view, _html} = open(c.conn)

      view |> element("#select-#{c.rent.id}") |> render_click()
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
               Categories.target_for(c.rent, @october)

      assert has_element?(view, "#inspector-target", "450,00 € bis 24. Dezember ansparen")
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
               Categories.target_for(c.rent, @october)

      assert has_element?(view, "#inspector-target", "Einmalig")
    end

    test "edits a repeating target after its due date", c do
      {:ok, _} =
        Categories.set_target(c.rent, %{
          from_month: ~D[2026-09-01],
          cadence: :by_date,
          amount: 30_000,
          due_on: ~D[2026-09-20],
          repeats_yearly: true
        })

      {:ok, view, _html} = open(c.conn)

      view |> element("#select-#{c.rent.id}") |> render_click()
      view |> element("#target-edit") |> render_click()

      assert has_element?(view, ~s|#target-due-on[value="2027-09-20"]|)

      view |> form("#target-form", %{"target" => %{"amount" => "360"}}) |> render_submit()

      assert %{amount: 36_000, due_on: ~D[2027-09-20], repeats_yearly: true} =
               Categories.target_for(c.rent, @october)
    end

    test "a target editor that is not filled in right says why and keeps what was typed", c do
      {:ok, view, _html} = open(c.conn)

      view |> element("#select-#{c.rent.id}") |> render_click()
      view |> element("#target-edit") |> render_click()

      view
      |> form("#target-form", %{"target" => %{"amount" => "viel"}})
      |> render_submit()

      assert has_element?(view, ~s|#target-amount.is-invalid[value="viel"]|)

      view
      |> form("#target-form", %{"target" => %{"cadence" => "by_date"}})
      |> render_change()

      view
      |> form("#target-form", %{
        "target" => %{"amount" => "300", "cadence" => "by_date", "due_on" => "2026-09-30"}
      })
      |> render_submit()

      assert has_element?(view, "#target-form .invalid-feedback", "nicht vor dem Beginn")
      assert Categories.target_for(c.rent, @october) == nil

      view |> element("#target-cancel") |> render_click()

      refute has_element?(view, "#target-form")
    end

    test "deletes a target from the focus month on", c do
      monthly(c.groceries, 40_000, ~D[2026-09-01])
      {:ok, view, _html} = open(c.conn)

      view |> element("#select-#{c.groceries.id}") |> render_click()
      view |> element("#target-edit") |> render_click()
      view |> element("#target-delete") |> render_click()

      assert Categories.target_for(c.groceries, @october) == nil
      assert Categories.target_for(c.groceries, ~D[2026-09-01]).amount == 40_000
      assert has_element?(view, "#inspector-target", "Kein Ziel")
    end

    test "snoozes the target in the focus month and resumes it", c do
      monthly(c.groceries, 40_000)
      {:ok, view, _html} = open(c.conn)

      view |> element("#select-#{c.groceries.id}") |> render_click()
      view |> element("#target-snooze", "Pausieren") |> render_click()

      assert Categories.target_snoozed?(c.groceries, @october)
      assert has_element?(view, "#inspector-target .badge", "pausiert")
      assert has_element?(view, "#inspector-target", "Im Oktober pausiert")
      assert has_element?(view, "#auto-underfunded[disabled]")
      assert has_element?(view, ~s|#category-#{c.groceries.id} .app-target[title="Pausiert"]|)

      view |> element("#target-snooze", "Fortsetzen") |> render_click()

      refute Categories.target_snoozed?(c.groceries, @october)
      assert has_element?(view, "#target-status", "Noch 400,00 € nötig")
    end

    test "auto-assign works on the selected category alone", c do
      income(c, 100_000)
      monthly(c.groceries, 40_000)
      monthly(c.rent, 50_000)
      Categories.assign(c.fuel, @october, 1_000)
      {:ok, view, _html} = open(c.conn)

      view |> element("#select-#{c.groceries.id}") |> render_click()
      view |> element("#auto-underfunded") |> render_click()

      assert assigned(c.groceries, @october) == 40_000
      assert assigned(c.rent, @october) == 0

      view |> element("#auto-reset") |> render_click()

      assert assigned(c.groceries, @october) == 0
      assert assigned(c.fuel, @october) == 1_000
    end

    test "without room for the inspector the category opens in a panel", c do
      {:ok, view, _html} = open(c.conn, inspector: false)

      refute has_element?(view, "#inspector")

      view |> element("#select-#{c.groceries.id}") |> render_click()

      assert has_element?(view, "#panel", "🛒 Lebensmittel")

      view |> element("#panel .btn-close") |> render_click()

      refute has_element?(view, "#panel")
    end

    test "another focus month closes the target editor", c do
      {:ok, view, _html} = open(c.conn, months: 2)

      view |> element("#select-#{c.groceries.id}") |> render_click()
      view |> element("#target-edit") |> render_click()
      view |> element("#month-2026-11") |> render_click()

      refute has_element?(view, "#target-form")
      assert has_element?(view, "#inspector", "November 2026")
    end
  end

  defp open(conn, opts \\ []) do
    fit = %{
      "months" => Keyword.get(opts, :months, 1),
      "inspector" => Keyword.get(opts, :inspector, true),
      "span" => 12
    }

    conn
    |> put_connect_params(%{"today" => "2026-10-10", "fit" => fit})
    |> live(~p"/")
  end

  defp monthly(category, amount, from \\ @october) do
    {:ok, _} =
      Categories.set_target(category, %{from_month: from, cadence: :monthly, amount: amount})
  end

  defp by_date(category, amount, due_on) do
    {:ok, _} =
      Categories.set_target(category, %{
        from_month: @october,
        cadence: :by_date,
        amount: amount,
        due_on: due_on
      })
  end

  defp income(c, amount, date \\ @october) do
    {:ok, payee} = Ledger.create_payee(%{name: "Arbeitgeber #{System.unique_integer()}"})

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
    Map.get(Categories.budget().assigned, {category.id, month}, 0)
  end
end
