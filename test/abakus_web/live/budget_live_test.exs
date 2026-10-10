defmodule AbakusWeb.BudgetLiveTest do
  use AbakusWeb.ConnCase

  import Phoenix.LiveViewTest
  import Abakus.DomainFixtures

  alias Abakus.{Categories, Ledger}

  @october ~D[2026-10-01]
  @november ~D[2026-11-01]

  test "anonymous visitors are sent to the sign-in page", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/")
  end

  describe "signed in" do
    setup :register_and_log_in_user

    setup do
      checking = account_fixture(kind: :checking)
      rta = Categories.ready_to_assign!()
      daily = category_group_fixture(name: "🛒 Alltag", position: 0)
      housing = category_group_fixture(name: "🏠 Wohnen", position: 1)
      groceries = category_fixture(name: "🛒 Lebensmittel", category_group_id: daily.id)
      rent = category_fixture(name: "🏠 Miete", category_group_id: housing.id)

      %{checking: checking, rta: rta, groceries: groceries, rent: rent}
    end

    test "the page has the sidebar with the budget link and the settings", %{conn: conn} do
      {:ok, view, _html} = open(conn)

      assert has_element?(view, "h1", "Budget")
      assert has_element?(view, ~s|aside nav a.active[aria-current=page][href="/"]|, "Budget")
      assert has_element?(view, ~s|aside a[href="/users/settings"]|, "Einstellungen")
      assert has_element?(view, "aside #side-toggle[phx-hook=SideToggle]")
      assert has_element?(view, ~s|aside #log-out[href="/users/log-out"][data-method=delete]|)
    end

    test "assigning in a month updates available, the totals and Zu verteilen", c do
      income(c, 100_000, ~D[2026-10-01], "Arbeitgeber")
      {:ok, view, _html} = open(c.conn)

      assert has_element?(view, "#ready-2026-10", "1.000,00 €")

      view |> element("#assign-#{c.groceries.id}-2026-10") |> render_blur(%{"value" => "250,5"})

      assert assigned(c.groceries, @october) == 25_050
      assert has_element?(view, "#available-#{c.groceries.id}-2026-10", "250,50 €")
      assert has_element?(view, "#total-2026-10-assigned", "250,50")

      assert has_element?(
               view,
               "#group-#{c.groceries.category_group_id}-2026-10-assigned",
               "250,50"
             )

      assert has_element?(view, "#ready-2026-10", "749,50 €")
      assert has_element?(view, ~s|#assign-#{c.groceries.id}-2026-10[value="250,50"]|)
    end

    test "an assignment is never refused, Zu verteilen goes below zero", c do
      income(c, 10_000, ~D[2026-10-01], "Arbeitgeber")
      {:ok, view, _html} = open(c.conn)

      view |> element("#assign-#{c.rent.id}-2026-10") |> render_blur(%{"value" => "1.050"})

      assert assigned(c.rent, @october) == 105_000
      assert has_element?(view, "#ready-2026-10.text-danger", "−950,00 €")
      assert has_element?(view, "#month-2026-10", "Zu viel verteilt")
    end

    test "an amount that is no number is marked and changes nothing", c do
      {:ok, view, _html} = open(c.conn)

      view |> element("#assign-#{c.groceries.id}-2026-10") |> render_blur(%{"value" => "zwölf"})

      assert assigned(c.groceries, @october) == 0

      assert has_element?(
               view,
               ~s|#assign-#{c.groceries.id}-2026-10.is-invalid[aria-invalid][value="zwölf"]|
             )

      view |> element("#assign-#{c.groceries.id}-2026-10") |> render_blur(%{"value" => "12"})

      assert assigned(c.groceries, @october) == 1_200
      refute has_element?(view, "#assign-#{c.groceries.id}-2026-10.is-invalid")
    end

    test "an unchanged amount writes nothing", c do
      {:ok, view, _html} = open(c.conn)

      view |> element("#assign-#{c.groceries.id}-2026-10") |> render_blur(%{"value" => "0,00"})

      assert Categories.budget().assigned == %{}
    end

    test "assigns only to shown months and visible categories", c do
      hidden = category_fixture(name: "Alt", category_group_id: c.groceries.category_group_id)
      Categories.update_category(hidden, %{hidden: true})
      {:ok, view, _html} = open(c.conn)

      for {id, month} <- [
            {hidden.id, "2026-10"},
            {c.groceries.id, "9999-12"},
            {c.rent.id, "2026-11"}
          ] do
        render_hook(view, "assign", %{"category" => "#{id}", "month" => month, "value" => "5"})
      end

      assert Categories.budget().assigned == %{}
    end

    test "the inspector warns while a later month is not covered, the month card with a sign",
         c do
      income(c, 100_000, ~D[2026-10-01], "Arbeitgeber")
      Categories.assign(c.groceries, @october, 40_000)
      spend(c, c.groceries, -80_000, ~D[2026-10-05])
      Categories.assign(c.rent, @november, 50_000)

      {:ok, view, _html} = open(c.conn, ~p"/", months: 2, inspector: true)

      assert has_element?(view, "#ready-2026-10", "100,00 €")
      warning = "November nicht gedeckt: es fehlen 300,00 €"
      assert has_element?(view, "#inspector .app-uncovered", warning)
      assert has_element?(view, ~s|#month-2026-10 .app-uncovered[title="#{warning}"]|)

      view |> element("#assign-#{c.rent.id}-2026-11") |> render_blur(%{"value" => "200"})

      refute has_element?(view, ".app-uncovered")
    end

    test "the current month is the focus month, with pills and its calculation in the inspector",
         c do
      income(c, 100_000, ~D[2026-10-01], "Arbeitgeber")
      Categories.assign(c.groceries, @october, 30_000)
      Categories.assign(c.groceries, @november, 30_000)
      {:ok, view, _html} = open(c.conn, ~p"/", months: 3, inspector: true)

      assert has_element?(
               view,
               "#month-2026-10.is-focus.is-current[aria-current=date]",
               "400,00 €"
             )

      assert has_element?(view, "#month-2026-11:not(.is-focus):not(.is-current)", "400,00 €")
      assert has_element?(view, "#month-2026-12:not(.is-focus)")
      refute has_element?(view, "#month-2026-10", "Verfügbare Mittel")
      assert has_element?(view, "#inspector", "Verfügbare Mittel")
      assert has_element?(view, "#inspector", "Für spätere Monate")
      assert has_element?(view, "#available-#{c.groceries.id}-2026-10 .app-pill", "300,00 €")
      assert has_element?(view, "#available-#{c.groceries.id}-2026-11 .app-q", "600,00")
      assert has_element?(view, "#strip button.is-focus", "Okt")
    end

    test "clicking a month card or working in a month makes it the focus month", c do
      {:ok, view, _html} = open(c.conn, ~p"/", months: 3)

      view |> element("#month-2026-11") |> render_click()

      assert has_element?(view, "#month-2026-11.is-focus")
      refute has_element?(view, "#month-2026-10.is-focus")

      view |> element("#assign-#{c.rent.id}-2026-12") |> render_focus()

      assert has_element?(view, "#month-2026-12.is-focus")
    end

    test "the first month comes from the URL; without the current month the first is the focus",
         c do
      {:ok, view, _html} = open(c.conn, ~p"/?month=2026-12", months: 2)

      assert has_element?(view, "#month-2026-12.is-focus")
      assert has_element?(view, "#month-2027-01:not(.is-focus)")
      refute has_element?(view, "#month-2026-10")
    end

    test "the current month is the browser's, unless its date is implausible", c do
      tomorrow = Date.add(Date.utc_today(), 1)
      {:ok, view, _html} = open(c.conn, ~p"/", today: Date.to_iso8601(tomorrow))
      assert has_element?(view, "#month-#{Calendar.strftime(tomorrow, "%Y-%m")}.is-current")

      {:ok, view, _html} = open(c.conn, ~p"/", today: "9999-12-31")

      assert has_element?(
               view,
               "#month-#{Calendar.strftime(Date.utc_today(), "%Y-%m")}.is-current"
             )
    end

    test "focusing a month that is not shown changes nothing", c do
      {:ok, view, _html} = open(c.conn)

      render_hook(view, "focus", %{"month" => "2027-05"})
      render_hook(view, "focus", %{"month" => "heute"})

      assert has_element?(view, "#month-2026-10.is-focus")
    end

    test "an unknown filter shows everything", c do
      income(c, 1_000, ~D[2026-10-01], "Arbeitgeber")
      {:ok, view, _html} = open(c.conn, ~p"/?filter=foo")

      assert has_element?(view, "#filters button[aria-pressed=true]", "Alle")
      assert has_element?(view, "#category-#{c.groceries.id}")
      assert has_element?(view, "#group-income-rows")
    end

    test "the window width decides the number of months and the inspector", c do
      {:ok, view, _html} = open(c.conn)

      assert has_element?(view, "#month-2026-10")
      refute has_element?(view, "#month-2026-11")
      refute has_element?(view, "#inspector")

      render_hook(view, "fit", %{"months" => 3, "inspector" => true, "span" => 12})

      assert has_element?(view, "#month-2026-12")
      assert has_element?(view, "#inspector", "Oktober 2026")

      render_hook(view, "fit", %{"months" => 7, "inspector" => "ja", "span" => 99})

      assert has_element?(view, "#month-2026-12")
      refute has_element?(view, "#month-2027-01")
      refute has_element?(view, "#inspector")

      render_hook(view, "fit", %{"months" => "3"})

      refute has_element?(view, "#month-2026-11")
    end

    test "the month strip moves the months and keeps the first one in the URL", c do
      {:ok, view, _html} = open(c.conn, ~p"/", months: 2)

      view |> element(~s|#strip button[aria-label="Später"]|) |> render_click()
      assert_patch(view, ~p"/?month=2026-11")
      assert has_element?(view, "#month-2026-11.is-focus")

      view |> element("#strip button", "Dez") |> render_click()
      assert has_element?(view, "#month-2026-12.is-focus")

      view |> element("#strip button", "Feb") |> render_click()
      assert_patch(view, ~p"/?month=2027-02")
      assert has_element?(view, "#month-2027-02.is-focus")
    end

    test "filter chips show only the categories in that state, counted in the focus month", c do
      Categories.assign(c.groceries, @october, 10_000)
      spend(c, c.rent, -5_000, ~D[2026-10-02])
      {:ok, view, _html} = open(c.conn)

      assert has_element?(view, "#filters button.btn-outline-danger", "1 überzogen")
      assert has_element?(view, "#category-#{c.groceries.id}")

      view |> element("#filters > button", "überzogen") |> render_click()

      assert_patch(view, ~p"/?filter=overspent&month=2026-10")
      assert has_element?(view, "#category-#{c.rent.id}")
      refute has_element?(view, "#category-#{c.groceries.id}")

      view |> element("#filters > button", "Geld verfügbar") |> render_click()

      assert has_element?(view, "#category-#{c.groceries.id}")
      refute has_element?(view, "#category-#{c.rent.id}")
    end

    test "groups show their totals; hidden categories and groups are left out", c do
      Categories.assign(c.groceries, @october, 10_000)
      hidden = category_fixture(name: "Alt", category_group_id: c.groceries.category_group_id)
      Categories.update_category(hidden, %{hidden: true})
      gone = category_group_fixture(name: "Weg", hidden: true)
      category_fixture(name: "Auch weg", category_group_id: gone.id)

      {:ok, view, _html} = open(c.conn)

      group = c.groceries.category_group_id

      assert has_element?(view, "#group-#{group} button[aria-expanded=true]", "Alltag")
      assert has_element?(view, "#group-#{group}-2026-10-assigned", "100,00")
      refute has_element?(view, "#category-#{hidden.id}")
      refute has_element?(view, "#group-#{gone.id}")
    end

    test "the income group lists the income per payee", c do
      income(c, 324_000, ~D[2026-10-01], "Arbeitgeber")
      income(c, 1_180, ~D[2026-10-03], "Bank")

      {:ok, view, _html} = open(c.conn)

      assert has_element?(view, "#group-income-2026-10-activity", "3.251,80")
      assert has_element?(view, "#group-income-rows tr", "Arbeitgeber")
      assert has_element?(view, "#group-income-rows tr", "Bank")
    end

    test "transactions without a category get a row of their own", c do
      spend(c, nil, -999, ~D[2026-10-08])

      {:ok, view, _html} = open(c.conn)

      assert has_element?(view, "#category-uncategorised", "Nicht kategorisiert")
      assert has_element?(view, "#available-uncategorised-2026-10 .text-bg-danger", "−9,99 €")
      assert has_element?(view, ~s|#category-uncategorised .app-target[title="Überzogen 9,99 €"]|)
      refute has_element?(view, "#assign-uncategorised-2026-10")
    end

    test "a target shows its bar under the name, the status on hover", c do
      Categories.set_target(c.groceries, %{
        from_month: @october,
        cadence: :monthly,
        amount: 70_000
      })

      Categories.assign(c.groceries, @october, 65_000)

      {:ok, view, _html} = open(c.conn)

      assert has_element?(
               view,
               ~s|#category-#{c.groceries.id} .app-target[title="Noch 50,00 € nötig"]|
             )

      refute has_element?(view, "#category-#{c.groceries.id} .app-line2", "50,00")
      assert has_element?(view, "#available-#{c.groceries.id}-2026-10 .text-bg-warning")
    end
  end

  defp open(conn, path \\ ~p"/", opts \\ []) do
    fit = %{
      "months" => Keyword.get(opts, :months, 1),
      "inspector" => Keyword.get(opts, :inspector, false),
      "span" => 12
    }

    conn
    |> put_connect_params(%{"today" => Keyword.get(opts, :today, "2026-10-10"), "fit" => fit})
    |> live(path)
  end

  defp income(c, amount, date, payee) do
    {:ok, payee} = Ledger.create_payee(%{name: payee})

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
    Map.get(Categories.budget().assigned, {category.id, month}, 0)
  end
end
