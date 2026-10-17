defmodule AbakusWeb.BudgetLiveTest do
  use AbakusWeb.ConnCase

  import Phoenix.LiveViewTest
  import Abakus.DomainFixtures

  alias Abakus.{Categories, Ledger}

  @october ~D[2026-10-01]
  @november ~D[2026-11-01]

  test "anonymous visitors are sent to the sign-in page", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/budget")
  end

  describe "signed in" do
    setup :register_and_log_in_user

    setup do
      checking = account_fixture(kind: :checking)
      rta = Categories.ready_to_assign!(budget_scope())
      daily = category_group_fixture(name: "🛒 Alltag", position: 0)
      housing = category_group_fixture(name: "🏠 Wohnen", position: 1)
      groceries = category_fixture(name: "🛒 Lebensmittel", category_group_id: daily.id)
      rent = category_fixture(name: "🏠 Miete", category_group_id: housing.id)

      %{checking: checking, rta: rta, groceries: groceries, rent: rent}
    end

    test "the page has the sidebar with the budget link and the settings", %{conn: conn} do
      {:ok, view, _html} = open(conn)

      assert has_element?(view, "h1", "Budget")
      assert has_element?(view, sidebar_link("/budget") <> "[aria-current=page]", "Budget")
      assert has_element?(view, sidebar_link("/settings"), "Einstellungen")
      assert has_element?(view, ~s|aside button[aria-label="Seitenleiste einklappen"]|)

      assert has_element?(
               view,
               ~s|aside #user-menu-sidebar a[href="/users/log-out"][data-method=delete]|,
               "Abmelden"
             )
    end

    test "assigning in a month updates available, the totals and Zu verteilen", c do
      income(c, 100_000, ~D[2026-10-01], "Arbeitgeber")
      {:ok, view, _html} = open(c.conn)

      assert has_element?(view, "#ready-2026-10", "1.000,00\u00A0€")

      view |> element("#assign-#{c.groceries.id}-2026-10") |> render_blur(%{"value" => "250,5"})

      assert assigned(c.groceries, @october) == 25_050
      assert has_element?(view, "#available-#{c.groceries.id}-2026-10", "250,50")
      assert has_element?(view, "#total-2026-10-assigned", "250,50")

      assert has_element?(
               view,
               "#group-#{c.groceries.category_group_id}-2026-10-assigned",
               "250,50"
             )

      assert has_element?(view, "#ready-2026-10", "749,50\u00A0€")
      assert has_element?(view, ~s|#assign-#{c.groceries.id}-2026-10[value="250,50"]|)
    end

    test "a category leaves zero assigned and activity blank, Verfügbar and the totals show 0,00",
         c do
      {:ok, view, _html} = open(c.conn)

      assert has_element?(view, "#assign-#{c.groceries.id}-2026-10:not([value])")
      assert view |> element("#activity-#{c.groceries.id}-2026-10") |> render() =~ ~r/>\s*<\/td>/
      assert has_element?(view, "#available-#{c.groceries.id}-2026-10", "0,00")

      assert has_element?(
               view,
               "#group-#{c.groceries.category_group_id}-2026-10-assigned",
               "0,00"
             )

      assert has_element?(view, "#total-2026-10-activity", "0,00")

      view |> element("#assign-#{c.groceries.id}-2026-10") |> render_blur(%{"value" => "12"})

      assert has_element?(view, ~s|#assign-#{c.groceries.id}-2026-10[value="12,00"]|)
    end

    test "an assignment is never refused, Zu verteilen goes below zero", c do
      income(c, 10_000, ~D[2026-10-01], "Arbeitgeber")
      {:ok, view, _html} = open(c.conn)

      view |> element("#assign-#{c.rent.id}-2026-10") |> render_blur(%{"value" => "1.050"})

      assert assigned(c.rent, @october) == 105_000
      assert has_element?(view, "#ready-2026-10", "−950,00\u00A0€")
      assert has_element?(view, "#ready-2026-10.text-error-ink")
      assert has_element?(view, "#calc-toggle-2026-10", "Zu verteilen")
    end

    test "an amount that is no number is marked and changes nothing", c do
      {:ok, view, _html} = open(c.conn)

      view |> element("#assign-#{c.groceries.id}-2026-10") |> render_blur(%{"value" => "zwölf"})

      assert assigned(c.groceries, @october) == 0

      assert has_element?(
               view,
               ~s|#assign-#{c.groceries.id}-2026-10[aria-invalid=true][value="zwölf"]|
             )

      view |> element("#assign-#{c.groceries.id}-2026-10") |> render_blur(%{"value" => "12"})

      assert assigned(c.groceries, @october) == 1_200
      refute has_element?(view, "#assign-#{c.groceries.id}-2026-10[aria-invalid]")
    end

    test "a blank amount assigns zero", c do
      for value <- ["", "  "] do
        Categories.assign(budget_scope(), c.groceries, @october, 1_200)
        {:ok, view, _html} = open(c.conn)

        view |> element("#assign-#{c.groceries.id}-2026-10") |> render_blur(%{"value" => value})

        assert assigned(c.groceries, @october) == 0
        refute has_element?(view, "#assign-#{c.groceries.id}-2026-10[aria-invalid]")
      end
    end

    test "an amount that is no text changes nothing", c do
      {:ok, view, _html} = open(c.conn)
      id = "#{c.groceries.id}"

      for value <- [%{"0" => "12"}, ["12"]] do
        render_hook(view, "assign", %{"category" => id, "month" => "2026-10", "value" => value})
      end

      assert Categories.budget(budget_scope()).assigned == %{}
    end

    test "an unchanged amount writes nothing", c do
      {:ok, view, _html} = open(c.conn)

      view |> element("#assign-#{c.groceries.id}-2026-10") |> render_blur(%{"value" => "0,00"})

      assert Categories.budget(budget_scope()).assigned == %{}
    end

    test "assigns only to shown months and listed categories", c do
      {:ok, view, _html} = open(c.conn)

      for {id, month} <- [
            {c.rta.id, "2026-10"},
            {c.groceries.id, "9999-12"},
            {c.rent.id, "2026-11"}
          ] do
        render_hook(view, "assign", %{"category" => "#{id}", "month" => month, "value" => "5"})
      end

      assert Categories.budget(budget_scope()).assigned == %{}
    end

    test "the month card warns while a later month is not covered", c do
      income(c, 100_000, ~D[2026-10-01], "Arbeitgeber")
      Categories.assign(budget_scope(), c.groceries, @october, 40_000)
      spend(c, c.groceries, -80_000, ~D[2026-10-05])
      Categories.assign(budget_scope(), c.rent, @november, 50_000)

      {:ok, view, _html} = open(c.conn, ~p"/budget", months: 2)

      assert has_element?(view, "#ready-2026-10", "100,00\u00A0€")
      assert has_element?(view, "#calc-2026-10 .app-mcalc-warn dt", "Nicht gedeckt im Nov")
      assert has_element?(view, "#calc-2026-10 .app-mcalc-warn dd", "−300,00\u00A0€")

      view |> element("#assign-#{c.rent.id}-2026-11") |> render_blur(%{"value" => "200"})

      refute has_element?(view, ".app-mcalc-warn")
    end

    test "Zu verteilen shows and hides the calculation of every month on the device", c do
      income(c, 100_000, ~D[2026-10-01], "Arbeitgeber")
      {:ok, view, _html} = open(c.conn, ~p"/budget", months: 3)

      for key <- ~w(2026-10 2026-11 2026-12) do
        assert has_element?(
                 view,
                 "#month-#{key} button#calc-toggle-#{key}[phx-hook=CalculationToggle]" <>
                   "[aria-expanded=false][aria-controls=calc-#{key}]",
                 "Zu verteilen"
               )

        assert has_element?(
                 view,
                 "#calc-toggle-#{key}[phx-mounted*=ignore_attrs][phx-mounted*=aria-expanded]"
               )

        assert has_element?(view, "#month-#{key} dl#calc-#{key} dt", "Einnahmen im")
      end
    end

    test "a card's ⋮ menu distributes the month", c do
      income(c, 100_000, ~D[2026-10-01], "Arbeitgeber")
      Categories.assign(budget_scope(), c.groceries, @october, 10_000)

      {:ok, _} =
        Categories.set_target(budget_scope(), c.rent, %{
          cadence: :monthly,
          amount: 6_834,
          from_month: @october
        })

      {:ok, view, _html} = open(c.conn, ~p"/budget")

      assert has_element?(
               view,
               ~s|#month-2026-10 #distribute-2026-10 summary.btn-ghost[aria-label="Verteilen"]|
             )

      refute has_element?(view, "#distribute-2026-10 summary", "Verteilen")

      assert has_element?(
               view,
               "#distribute-underfunded-2026-10",
               "Unterfinanzierte füllen (68,34\u00A0€)"
             )

      assert has_element?(view, "#distribute-pick-2026-10", "In eine Kategorie …")
      assert has_element?(view, "#distribute-reset-2026-10", "Zuweisung zurücksetzen")
    end

    test "the current month is the focus month; a card has its calculation", c do
      income(c, 100_000, ~D[2026-10-01], "Arbeitgeber")
      Categories.assign(budget_scope(), c.groceries, @october, 30_000)
      Categories.assign(budget_scope(), c.groceries, @november, 30_000)
      {:ok, view, _html} = open(c.conn, ~p"/budget", months: 3)

      assert has_element?(
               view,
               "#month-2026-10.is-focus[aria-current=date]",
               "400,00\u00A0€"
             )

      assert has_element?(
               view,
               "#month-2026-11:not(.is-focus):not([aria-current])",
               "400,00\u00A0€"
             )

      assert has_element?(view, "#month-2026-12:not(.is-focus)")
      assert has_element?(view, "#month-2026-10 #calc-2026-10", "Für spätere Monate")
      assert has_element?(view, "#calc-2026-10", "−300,00")
      refute has_element?(view, "#calc-2026-11", "Für spätere Monate")
      refute has_element?(view, "#month-details-2026-10")
      assert has_element?(view, "#available-button-#{c.groceries.id}-2026-10", "300,00")
      assert has_element?(view, "#available-button-#{c.groceries.id}-2026-11", "600,00")
      assert has_element?(view, "#strip button.is-focus", "Okt")
    end

    test "clicking a month card or working in a month makes it the focus month", c do
      {:ok, view, _html} = open(c.conn, ~p"/budget", months: 3)

      view |> element("#month-2026-11") |> render_click()

      assert has_element?(view, "#month-2026-11.is-focus")
      refute has_element?(view, "#month-2026-10.is-focus")

      view |> element("#assign-#{c.rent.id}-2026-12") |> render_focus()

      assert has_element?(view, "#month-2026-12.is-focus")
    end

    test "the first month comes from the URL; without the current month the first is the focus",
         c do
      {:ok, view, _html} = open(c.conn, ~p"/budget?month=2026-12", months: 2)

      assert has_element?(view, "#month-2026-12.is-focus")
      assert has_element?(view, "#month-2027-01:not(.is-focus)")
      refute has_element?(view, "#month-2026-10")
    end

    test "the current month is the host's local one", c do
      {:ok, view, _html} = open(c.conn, ~p"/budget", today: ~D[2031-03-15])

      assert has_element?(view, "#month-2031-03[aria-current=date]")
    end

    test "focusing a month that is not shown changes nothing", c do
      {:ok, view, _html} = open(c.conn)

      render_hook(view, "focus", %{"month" => "2027-05"})
      render_hook(view, "focus", %{"month" => "heute"})

      assert has_element?(view, "#month-2026-10.is-focus")
    end

    test "the window width decides the number of months", c do
      {:ok, view, _html} = open(c.conn)

      assert has_element?(view, "#month-2026-10")
      refute has_element?(view, "#month-2026-11")

      render_hook(view, "fit", %{"months" => 3, "span" => 12})

      assert has_element?(view, "#month-2026-12")

      render_hook(view, "fit", %{"months" => 7, "span" => 99})

      assert has_element?(view, "#month-2026-12")
      refute has_element?(view, "#month-2027-01")

      render_hook(view, "fit", %{"months" => "3"})

      refute has_element?(view, "#month-2026-11")
    end

    test "a compact budget shows its month in a bar that steps through the months", c do
      income(c, 100_000, ~D[2026-10-01], "Arbeitgeber")
      {:ok, view, _html} = open(c.conn, ~p"/budget", compact: true, months: 3)

      refute has_element?(view, "#strip")
      refute has_element?(view, "#month-2026-11")
      assert has_element?(view, "#month-bar", "Oktober 2026")
      assert has_element?(view, "#month-bar #ready-2026-10", "1.000,00\u00A0€")

      assert has_element?(
               view,
               ~s|#month-bar #distribute-2026-10 summary[aria-label="Verteilen"]|
             )

      assert has_element?(
               view,
               "#month-bar #calc-toggle-2026-10[aria-expanded][aria-controls=calc-2026-10]",
               "Zu verteilen"
             )

      assert has_element?(view, "#month-bar #calc-2026-10", "Einnahmen im Okt")
      assert has_element?(view, ".app-add-end #add-group")
      refute has_element?(view, "thead #add-group")

      view |> element(~s|#month-bar button[aria-label="Später"]|) |> render_click()

      assert_patch(view, ~p"/budget?month=2026-11")
      assert has_element?(view, "#month-bar", "November 2026")
    end

    test "the month strip moves the months and keeps the first one in the URL", c do
      {:ok, view, _html} = open(c.conn, ~p"/budget", months: 2)

      view |> element(~s|#strip button[aria-label="Später"]|) |> render_click()
      assert_patch(view, ~p"/budget?month=2026-11")
      assert has_element?(view, "#month-2026-11.is-focus")

      view |> element("#strip button", "Dez") |> render_click()
      assert has_element?(view, "#month-2026-12.is-focus")

      view |> element("#strip button", "Feb") |> render_click()
      assert_patch(view, ~p"/budget?month=2027-02")
      assert has_element?(view, "#month-2027-02.is-focus")
    end

    test "groups show their totals; categories and groups hidden in YNAB are shown", c do
      Categories.assign(budget_scope(), c.groceries, @october, 10_000)
      hidden = category_fixture(name: "Alt", category_group_id: c.groceries.category_group_id)
      Categories.update_category(budget_scope(), hidden, %{hidden: true})
      gone = category_group_fixture(name: "Weg", hidden: true)
      category_fixture(name: "Auch weg", category_group_id: gone.id)

      {:ok, view, _html} = open(c.conn)

      group = c.groceries.category_group_id

      assert has_element?(
               view,
               ~s|#group-#{group} button[aria-expanded=true][aria-label="🛒 Alltag auf- und zuklappen"]|
             )

      assert has_element?(view, "#group-#{group}-2026-10-assigned", "100,00")
      assert has_element?(view, "#category-#{hidden.id}", "Alt")
      assert has_element?(view, "#group-#{gone.id}", "Weg")
    end

    test "income goes into Zu verteilen and has no group of its own", c do
      income(c, 324_000, ~D[2026-10-01], "Arbeitgeber")

      {:ok, view, _html} = open(c.conn)

      assert has_element?(view, "#ready-2026-10", "3.240,00\u00A0€")
      refute has_element?(view, "#group-income")
      refute render(view) =~ "Arbeitgeber"
    end

    test "transactions without a category get a row of their own", c do
      spend(c, nil, -999, ~D[2026-10-08])

      {:ok, view, _html} = open(c.conn)

      assert has_element?(view, "#category-uncategorised", "Nicht kategorisiert")

      assert has_element?(
               view,
               "#available-uncategorised-2026-10 span.app-avail.text-error-ink",
               "\u22129,99"
             )

      assert has_element?(view, "#available-uncategorised-2026-10 .sr-only", "überzogen")
      refute has_element?(view, "#available-uncategorised-2026-10 button")
      assert has_element?(view, ~s|#category-uncategorised a[href="/budget/accounts/all"]|)

      refute has_element?(view, "#assign-uncategorised-2026-10")
    end

    test "Verfügbar shows its state the same in a later month, without pills, and opens its popover there",
         c do
      fuel = category_fixture(name: "⛽ Tanken", category_group_id: c.groceries.category_group_id)
      gift = category_fixture(name: "🎁 Geschenke", category_group_id: c.rent.category_group_id)

      for {category, amount} <- [{c.groceries, 10_000}, {c.rent, 50_000}, {fuel, 5_000}] do
        Categories.set_target(budget_scope(), category, %{
          from_month: @october,
          cadence: :monthly,
          amount: amount
        })
      end

      Categories.assign(budget_scope(), c.groceries, @november, 10_000)
      Categories.assign(budget_scope(), c.rent, @november, 20_000)
      Categories.snooze_target(budget_scope(), fuel, @november)
      spend(c, gift, -1_000, ~D[2026-11-05])

      {:ok, view, _html} = open(c.conn, ~p"/budget", months: 2)

      assert has_element?(view, "#month-2026-10.is-focus")
      refute has_element?(view, ".app-pill")

      button = &"#available-button-#{&1.id}-2026-11"

      assert has_element?(
               view,
               button.(c.groceries) <> ~s|[aria-label*="Ziel erreicht"]|,
               "100,00"
             )

      assert has_element?(view, button.(c.groceries) <> " .lucide.text-success-ink")

      refute has_element?(
               view,
               button.(c.groceries) <> ":is(.text-success-ink, .text-warning-ink)"
             )

      assert has_element?(
               view,
               button.(c.rent) <> ~s|.text-warning-ink[aria-label*="unterfinanziert"]|,
               "200,00"
             )

      assert has_element?(view, button.(c.rent) <> " .lucide")
      assert has_element?(view, button.(fuel) <> ~s|[aria-label*="Ziel pausiert"] .lucide|)
      refute has_element?(view, button.(fuel) <> ".text-warning-ink")
      assert has_element?(view, button.(gift) <> ~s|.text-error-ink[aria-label*="überzogen"]|)

      view |> element(button.(c.rent)) |> render_click()

      assert has_element?(view, "#month-2026-11.is-focus")
      assert has_element?(view, ~s|#popover[data-anchor="available-button-#{c.rent.id}-2026-11"]|)
      assert has_element?(view, "#popover", "November 2026")
      assert has_element?(view, "#popover #move-form")
    end

    test "an underfunded target shows only in the current month and months with assignments", c do
      Categories.set_target(budget_scope(), c.rent, %{
        from_month: @october,
        cadence: :monthly,
        amount: 50_000
      })

      {:ok, view, _html} = open(c.conn, ~p"/budget", months: 3)

      cell = &"#available-button-#{c.rent.id}-#{&1}"

      assert has_element?(
               view,
               cell.("2026-10") <> ~s|.text-warning-ink[aria-label*="unterfinanziert"]|
             )

      refute has_element?(view, cell.("2026-12") <> ~s|[aria-label*="unterfinanziert"]|)
      refute has_element?(view, cell.("2026-12") <> " .lucide")
      refute has_element?(view, cell.("2026-12") <> ".text-warning-ink")

      view |> element("#assign-#{c.groceries.id}-2026-12") |> render_blur(%{"value" => "10"})

      assert has_element?(
               view,
               cell.("2026-12") <> ~s|.text-warning-ink[aria-label*="unterfinanziert"]|
             )

      assert has_element?(view, cell.("2026-12") <> " .lucide")
    end

    test "a target shows its state in Verfügbar, not on the row", c do
      Categories.set_target(budget_scope(), c.groceries, %{
        from_month: @october,
        cadence: :monthly,
        amount: 70_000
      })

      Categories.assign(budget_scope(), c.groceries, @october, 65_000)

      {:ok, view, _html} = open(c.conn)

      refute has_element?(view, "#category-#{c.groceries.id}", "Unterfinanziert")

      assert has_element?(
               view,
               ~s|#available-button-#{c.groceries.id}-2026-10[aria-label*="unterfinanziert"]|
             )
    end
  end

  describe "the target status" do
    setup :register_and_log_in_user

    setup do
      checking = account_fixture(kind: :checking)
      group = category_group_fixture(name: "🛒 Alltag")
      category = category_fixture(name: "🧴 Drogerie", category_group_id: group.id)

      {:ok, _} =
        Categories.set_target(budget_scope(), category, %{
          from_month: @october,
          cadence: :monthly,
          amount: 1_000
        })

      Categories.assign(budget_scope(), category, @october, 1_000)
      %{checking: checking, category: category}
    end

    test "stays funded when everything assigned is spent", c do
      transaction_fixture(account_id: c.checking.id, category_id: c.category.id, amount: -1_000)
      {:ok, view, _html} = open(c.conn)

      view |> element("#select-#{c.category.id}") |> render_click()

      assert has_element?(view, "#target-status.text-success-ink", "Erfüllt.")
      refute has_element?(view, "#target-progress")
      refute has_element?(view, "#target-assign")
      refute has_element?(view, "#inspector-target", "ausgegeben")
      refute has_element?(view, "#inspector-target", "Ziel diesen Monat")
    end

    test "turns red once more is spent than assigned", c do
      transaction_fixture(account_id: c.checking.id, category_id: c.category.id, amount: -1_200)
      {:ok, view, _html} = open(c.conn)

      assert has_element?(view, "#available-#{c.category.id}-2026-10 .app-avail.text-error-ink")

      view |> element("#select-#{c.category.id}") |> render_click()

      assert has_element?(view, "#target-status.text-error-ink", "Überzogen um 2,00\u00A0€.")
    end
  end

  describe "without categories" do
    setup :register_and_log_in_user

    test "the budget says how to start", c do
      {:ok, view, _html} = open(c.conn)

      assert has_element?(view, "#budget-table #budget-empty", "Noch keine Kategorien")

      view |> element("#budget-empty button", "Gruppe anlegen") |> render_click()

      assert has_element?(view, "#edit-pop", "Neue Kategoriegruppe")
    end
  end

  defp open(conn, path \\ ~p"/budget", opts \\ []) do
    fit = %{
      "months" => Keyword.get(opts, :months, 1),
      "span" => 12,
      "compact" => Keyword.get(opts, :compact, false)
    }

    fix_today(Keyword.get(opts, :today, ~D[2026-10-10]))

    conn
    |> put_connect_params(%{"fit" => fit})
    |> live(path)
  end

  defp income(c, amount, date, payee) do
    {:ok, payee} = Ledger.create_payee(budget_scope(), %{name: payee})

    transaction_fixture(
      account_id: c.checking.id,
      category_id: c.rta.id,
      payee_id: payee.id,
      amount: amount,
      date: date
    )
  end

  defp spend(c, category, amount, date) do
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
