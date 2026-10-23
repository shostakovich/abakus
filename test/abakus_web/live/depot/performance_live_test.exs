defmodule AbakusWeb.Depot.PerformanceLiveTest do
  use AbakusWeb.ConnCase

  import Phoenix.LiveViewTest
  import Abakus.Depot.{PortfoliosFixtures, SecuritiesFixtures}

  alias Abakus.Depot.Portfolios.TransactionUnit
  alias Abakus.Depot.Securities.Security
  alias Abakus.{Format, LocalTime, Repo}

  setup :register_and_log_in_user

  defp today, do: LocalTime.today()

  # „Langfristig“: 10 shares at 100 € + 2 € fee two years ago, 90 € a year ago, 110 € today.
  # „Sparplan“: 500 € since yesterday.
  setup %{scope: scope} do
    account = account_fixture(scope, %{name: "Konto Langfristig"})
    portfolio = portfolio_fixture(scope, %{name: "Langfristig", reference_account_id: account.id})
    two_years_ago = Date.shift(today(), year: -2)

    security =
      security_fixture(quote_feed: :manual, latest_date: today(), latest_close: price(110))

    price_fixture(security, two_years_ago, price(100), :manual)
    price_fixture(security, Date.shift(today(), year: -1), price(90), :manual)

    transaction_fixture(scope, two_years_ago,
      type: :deposit,
      account_id: account.id,
      amount: money(1_002)
    )

    transaction_fixture(scope, two_years_ago,
      type: :buy,
      portfolio_id: portfolio.id,
      account_id: account.id,
      security_id: security.id,
      shares: shares(10),
      amount: money(1_002),
      units: [%TransactionUnit{type: :fee, amount: money(2)}]
    )

    savings = account_fixture(scope, %{name: "Konto Sparplan"})
    sparplan = portfolio_fixture(scope, %{name: "Sparplan", reference_account_id: savings.id})

    transaction_fixture(scope, Date.add(today(), -1),
      type: :deposit,
      account_id: savings.id,
      amount: money(500)
    )

    %{portfolio: portfolio, sparplan: sparplan}
  end

  test "is a tab of the Depots", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/depot/performance")

    assert has_element?(lv, ~s(#depots-tabs a[href="/depot/performance"][aria-current=page]))
    assert has_element?(lv, sidebar_link("/depot/holdings") <> "[aria-current=page]")
  end

  test "shows the key figures of all portfolios for the year to date", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/depot/performance")

    assert has_element?(lv, "#period a[aria-current]", "YTD")
    assert has_element?(lv, "#portfolio-menu summary", "Gesamt")
    assert has_element?(lv, "h1", "Depots")
    assert has_element?(lv, "#ttwror .stat-value")
    assert lv |> element("#ttwror") |> render() =~ "p.\u00A0a."
    assert has_element?(lv, "#irr .stat-value")
    assert has_element?(lv, "#drawdown .stat-title", "Max. Drawdown")
    assert has_element?(lv, "#volatility .stat-title", "Volatilität")
  end

  test "breaks down the change in value from the initial to the final value", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/depot/performance?period=max")

    breakdown = lv |> element("#breakdown") |> render()
    first_day = Date.shift(today(), year: -2) |> Date.add(-1) |> Format.date()

    assert breakdown =~ "Anfangswert am #{first_day}"
    assert breakdown =~ "0,00\u00A0€"
    assert breakdown =~ ~r/Unrealisierte Kursgewinne.*\+100,00\x{00A0}€/su
    assert breakdown =~ ~r/Gebühren.*−2,00\x{00A0}€/su
    assert breakdown =~ ~r/Einlagen und Entnahmen.*\+1.502,00\x{00A0}€/su

    assert breakdown =~
             ~r/Endwert am #{Format.date(today())}.*1.600,00\x{00A0}€/su
  end

  test "shows the largest fall with its days", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/depot/performance?period=max")

    drawdown = lv |> element("#drawdown") |> render()

    assert drawdown =~ "−10,00\u00A0%"
    assert drawdown =~ Format.date(Date.shift(today(), year: -2))
    assert drawdown =~ Format.date(Date.shift(today(), year: -1))
  end

  describe "monthly returns" do
    defp cells(lv, year) do
      lv
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("#monthly-returns-#{year} td")
      |> Enum.map(&(&1 |> LazyHTML.text() |> String.trim()))
    end

    test "show every year since the first transaction, newest first, whatever the period", ctx do
      {:ok, lv, _html} = live(ctx.conn, ~p"/depot/performance?period=1m")

      years =
        lv
        |> render()
        |> LazyHTML.from_fragment()
        |> LazyHTML.query("#monthly-returns tbody th")
        |> Enum.map(&(&1 |> LazyHTML.text() |> String.trim()))

      assert years == Enum.map(0..2, &Integer.to_string(today().year - &1))
      assert has_element?(lv, "#monthly-returns thead th.app-heatmap-total", "Jahr")
    end

    test "leave the months before the first transaction and after today empty", ctx do
      {:ok, lv, _html} = live(ctx.conn, ~p"/depot/performance")
      first_month = Date.shift(today(), year: -2).month

      first_year = lv |> cells(today().year - 2) |> Enum.map(&String.match?(&1, ~r/^\D*\d/))

      assert first_year ==
               List.duplicate(false, first_month - 1) ++ List.duplicate(true, 14 - first_month)

      this_year = lv |> cells(today().year) |> Enum.map(&(&1 == "keine Daten"))

      assert this_year ==
               List.duplicate(false, today().month) ++
                 List.duplicate(true, 12 - today().month) ++ [false]
    end

    test "chain the months to the year", ctx do
      # 900 € in shares on 31 December and 500 € coming in yesterday; 1,600 € today.
      {:ok, lv, _html} = live(ctx.conn, ~p"/depot/performance")

      cells = cells(lv, today().year)
      assert Enum.at(cells, today().month - 1) =~ "+14,3"
      assert List.last(cells) =~ "+14,29"
    end

    test "follow the portfolio", ctx do
      {:ok, lv, _html} = live(ctx.conn, ~p"/depot/performance?#{[portfolio: ctx.sparplan.id]}")

      cells = cells(lv, today().year)
      assert Enum.at(cells, today().month - 1) == "±0,0"
      assert List.last(cells) == "±0,00"
    end
  end

  test "keeps the period and the portfolio in the URL, so that they survive a reload", ctx do
    {:ok, lv, _html} = live(ctx.conn, ~p"/depot/performance")

    lv |> element("#period a", "1\u00A0M") |> render_click()
    assert_patch(lv, ~p"/depot/performance?period=1m")

    lv |> element("#portfolio-menu a", "Sparplan") |> render_click()
    path = ~p"/depot/performance?#{[period: "1m", portfolio: ctx.sparplan.id]}"
    assert_patch(lv, path)

    {:ok, lv, _html} = live(ctx.conn, path)

    assert has_element?(lv, "#period a[aria-current]", "1\u00A0M")
    assert has_element?(lv, "#portfolio-menu summary", "Sparplan")

    assert lv |> element("#breakdown") |> render() =~
             ~r/Einlagen und Entnahmen.*\+500,00\x{00A0}€/su

    lv |> element("#period a", "3\u00A0J") |> render_click()
    assert_patch(lv, ~p"/depot/performance?#{[period: "3y", portfolio: ctx.sparplan.id]}")
  end

  test "falls back to the year to date and all portfolios for unknown parameters", ctx do
    {:ok, lv, _html} = live(ctx.conn, ~p"/depot/performance?period=decade&portfolio=nope")

    assert has_element?(lv, "#period a[aria-current]", "YTD")
    assert has_element?(lv, "#portfolio-menu summary", "Gesamt")
  end

  test "updates when new prices arrive", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/depot/performance?period=max")

    Repo.update_all(Security, set: [latest_close: price(120)])
    send(lv.pid, :market_data_updated)

    assert lv |> element("#breakdown") |> render() =~ ~r/Endwert.*1.700,00\x{00A0}€/su
  end
end
