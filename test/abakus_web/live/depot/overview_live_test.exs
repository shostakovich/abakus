defmodule AbakusWeb.Depot.OverviewLiveTest do
  use AbakusWeb.ConnCase

  import Phoenix.LiveViewTest
  import Abakus.Depot.{PortfoliosFixtures, SecuritiesFixtures}

  alias Abakus.Depot.Portfolios.TransactionUnit
  alias Abakus.Depot.Securities.Security
  alias Abakus.LocalTime
  alias Abakus.Repo
  alias AbakusWeb.Depot.Format

  setup :register_and_log_in_user

  defp today, do: LocalTime.today()

  defp holding_fixture(scope, count, attrs \\ []) do
    security =
      security_fixture(quote_feed: :manual, latest_date: today(), latest_close: price(102))

    price_fixture(security, Date.add(today(), -1), price(100), :pp)

    transaction_fixture(
      scope,
      Date.add(today(), -1),
      [
        type: :inbound_delivery,
        portfolio_id: portfolio_fixture(scope).id,
        security_id: security.id,
        shares: shares(count)
      ] ++ attrs
    )

    security
  end

  test "shows net worth and its change since yesterday", %{conn: conn, scope: scope} do
    holding_fixture(scope, 10)

    {:ok, lv, _html} = live(conn, ~p"/depot")

    assert lv |> element("#net-worth") |> render() =~ "1.020\u00A0€"

    assert has_element?(lv, "#net-worth .text-success-ink", "+20\u00A0€ heute (+2,00\u00A0%)")
  end

  test "shows a loss since yesterday in red", %{conn: conn, scope: scope} do
    security = holding_fixture(scope, 10)
    Repo.update!(Ecto.Changeset.change(security, latest_close: price(97.5)))

    {:ok, lv, _html} = live(conn, ~p"/depot")

    assert lv |> element("#net-worth") |> render() =~ "975\u00A0€"

    assert has_element?(lv, "#net-worth .text-error-ink", "−25\u00A0€ heute (−2,50\u00A0%)")
  end

  test "shows a change that rounds to 0 € without a colour", %{conn: conn, scope: scope} do
    security = holding_fixture(scope, 100)
    Repo.update!(Ecto.Changeset.change(security, latest_close: price(99.996)))

    {:ok, lv, _html} = live(conn, ~p"/depot")

    assert has_element?(lv, "#net-worth [class~=\"text-base-content/70\"]", ~r/^0\s€ heute/u)
  end

  test "shows the change without a percentage when there was nothing yesterday", ctx do
    account = account_fixture(ctx.scope)
    portfolio_fixture(ctx.scope, reference_account_id: account.id)

    transaction_fixture(ctx.scope, today(),
      type: :deposit,
      account_id: account.id,
      amount: money(500)
    )

    {:ok, lv, _html} = live(ctx.conn, ~p"/depot")

    assert has_element?(lv, "#net-worth .text-success-ink", ~r/^\+500\x{00A0}€ heute$/u)
  end

  test "updates when new prices arrive", %{conn: conn, scope: scope} do
    security = holding_fixture(scope, 10)
    {:ok, lv, _html} = live(conn, ~p"/depot")

    Repo.update!(Ecto.Changeset.change(security, latest_close: price(110)))
    send(lv.pid, :market_data_updated)

    assert lv |> element("#net-worth") |> render() =~ "1.100\u00A0€"
  end

  describe "Wertentwicklung" do
    # 1,000 € deposited two years ago, 500 € of shares delivered yesterday, quoted at 102 € today.
    setup %{scope: scope} do
      account = account_fixture(scope)

      transaction_fixture(scope, Date.shift(today(), year: -2),
        type: :deposit,
        account_id: account.id,
        amount: money(1_000)
      )

      holding_fixture(scope, 5, amount: money(500))
      :ok
    end

    test "shows net worth against invested capital for six months", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/depot")

      assert has_element?(lv, "#period a[aria-current]", "6\u00A0M")
      assert_push_event(lv, "net-worth-chart", %{dates: dates} = chart)
      assert dates == Enum.to_list(Date.range(Date.shift(today(), month: -6), today()))
      assert List.last(chart.net_worth) == money(1_510)
      assert List.last(chart.invested_capital) == money(1_500)
      assert Enum.at(chart.invested_capital, -3) == money(1_000)
    end

    test "keeps the period in the URL, so that it survives a reload", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/depot")
      assert_push_event(lv, "net-worth-chart", _six_months)

      lv |> element("#period a", "YTD") |> render_click()

      assert_patch(lv, ~p"/depot?period=ytd")
      assert_push_event(lv, "net-worth-chart", %{dates: [first | _]})
      assert first == Date.new!(today().year, 1, 1)

      {:ok, lv, _html} = live(conn, ~p"/depot?period=ytd")

      assert has_element?(lv, "#period a[aria-current]", "YTD")
      assert_push_event(lv, "net-worth-chart", %{dates: [^first | _]})
    end

    test "shows everything since the first transaction as Max", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/depot?period=max")

      assert has_element?(lv, "#period a[aria-current]", "Max")
      assert_push_event(lv, "net-worth-chart", %{dates: [first | _] = dates})
      assert first == Date.shift(today(), year: -2)
      assert List.last(dates) == today()
    end

    test "falls back to six months for an unknown period", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/depot?period=decade")

      assert has_element?(lv, "#period a[aria-current]", "6\u00A0M")
    end

    test "updates when new prices arrive", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/depot")
      assert_push_event(lv, "net-worth-chart", _before)

      Repo.update_all(Security, set: [latest_close: price(110)])
      send(lv.pid, :market_data_updated)

      assert_push_event(lv, "net-worth-chart", %{net_worth: net_worth})
      assert List.last(net_worth) == money(1_550)
    end

    # The shares came in at 100 € yesterday and are quoted at 102 € today: 1,510 € on 1,500 €.
    test "shows TTWROR and IRR for the period", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/depot")

      assert lv |> element("#ttwror .stat-title") |> render() =~ "TTWROR\u2060\u00A0· 6\u00A0M"
      assert lv |> element("#ttwror .stat-value.text-success-ink") |> render() =~ "+0,67\u00A0%"
      assert lv |> element("#irr .stat-title") |> render() =~ "IZF\u2060\u00A0· 6\u00A0M"

      assert lv |> element("#irr .stat-value.text-success-ink") |> render() =~
               ~r/\+\d+,\d\d\x{00A0}%/u

      assert lv |> element("#irr") |> render() =~ "p.\u00A0a.\u2060\u00A0· geldgewichtet"

      lv |> element("#period a", "Max") |> render_click()

      assert lv |> element("#ttwror .stat-title") |> render() =~ "TTWROR\u2060\u00A0· Max"
      assert lv |> element("#ttwror .stat-value") |> render() =~ "+0,67\u00A0%"
      assert lv |> element("#irr .stat-title") |> render() =~ "IZF\u2060\u00A0· Max"
    end

    test "updates the returns when new prices arrive", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/depot")

      Repo.update_all(Security, set: [latest_close: price(97)])
      send(lv.pid, :market_data_updated)

      assert lv |> element("#ttwror .stat-value.text-error-ink") |> render() =~ "−1,00\u00A0%"
    end
  end

  test "shows this year's dividends before taxes and fees", %{conn: conn, scope: scope} do
    security = holding_fixture(scope, 10)
    account = account_fixture(scope)

    for {date, net, tax, fee} <- [
          {today(), 15, 4, 1},
          {Date.new!(today().year, 1, 1), 30, 0, 0},
          {Date.new!(today().year - 1, 12, 31), 99, 0, 0}
        ] do
      transaction_fixture(scope, date,
        type: :dividend,
        account_id: account.id,
        security_id: security.id,
        amount: money(net),
        units: [
          %TransactionUnit{type: :tax, amount: money(tax), currency: "EUR"},
          %TransactionUnit{type: :fee, amount: money(fee), currency: "EUR"}
        ]
      )
    end

    {:ok, lv, _html} = live(conn, ~p"/depot")

    assert lv |> element("#dividends .stat-title") |> render() =~ "Dividenden #{today().year}"
    assert lv |> element("#dividends .stat-value") |> render() =~ "50\u00A0€"
  end

  describe "Nächste Dividenden" do
    setup %{scope: scope} do
      security = holding_fixture(scope, 100, amount: money(10_000))
      Repo.update!(Ecto.Changeset.change(security, name: "All-World"))
      announced = Date.add(today(), 1)
      forecast = today() |> Date.beginning_of_month() |> Date.shift(month: 2) |> Date.add(14)
      divvy_diary_dividend_fixture(security, announced, announced, 0.5)

      divvy_diary_dividend_fixture(
        security,
        Date.shift(forecast, year: -1) |> Date.add(-7),
        Date.shift(forecast, year: -1),
        1
      )

      %{announced: announced, forecast: forecast}
    end

    test "expects this year's received plus the rest of the year's dividends", ctx do
      transaction_fixture(ctx.scope, Date.new!(today().year, 1, 1),
        type: :dividend,
        account_id: account_fixture(ctx.scope).id,
        security_id: Repo.one!(Security).id,
        amount: money(30)
      )

      {:ok, lv, _html} = live(ctx.conn, ~p"/depot")

      rest =
        for {date, gross} <- [{ctx.announced, 50}, {ctx.forecast, 100}],
            date.year == today().year,
            reduce: 0,
            do: (sum -> sum + gross)

      expected = Regex.escape(Format.euros(money(30 + rest)))
      assert has_element?(lv, "#dividends .stat-desc", ~r/erwartet\s+#{expected} im Jahr/u)
    end

    test "lists the next dividends, gross, each marked announced or forecast", ctx do
      {:ok, lv, _html} = live(ctx.conn, ~p"/depot")

      announced = lv |> element("#upcoming-dividends li[data-kind='announced']") |> render()
      assert announced =~ "All\u2011World"
      assert announced =~ "angekündigt"
      assert announced =~ "50,00\u00A0€"
      assert announced =~ Date.to_iso8601(ctx.announced)

      forecast = lv |> element("#upcoming-dividends li[data-kind='forecast']") |> render()
      assert forecast =~ "Prognose"
      assert forecast =~ "~100,00\u00A0€"

      assert has_element?(
               lv,
               "#upcoming-dividends a[href='/depot/dividends?amount=gross']",
               "Kalender"
             )

      assert lv |> element("#upcoming-dividends-total") |> render() =~ "~150\u00A0€"
    end

    test "keep when the period changes and update when new market data arrives", ctx do
      {:ok, lv, _html} = live(ctx.conn, ~p"/depot")
      divvy_diary_dividend_fixture(Repo.one!(Security), nil, Date.add(today(), 2), 0.1)

      lv |> element("#period a", "Max") |> render_click()

      assert upcoming_count(lv) == 2

      send(lv.pid, :market_data_updated)

      assert upcoming_count(lv) == 3
    end

    test "shows the four next dividends", ctx do
      security = Repo.one!(Security)

      for days <- 4..8,
          do: divvy_diary_dividend_fixture(security, nil, Date.add(today(), days), 0.1)

      {:ok, lv, _html} = live(ctx.conn, ~p"/depot")

      assert upcoming_count(lv) == 4
    end

    defp upcoming_count(lv),
      do:
        lv
        |> element("#upcoming-dividends")
        |> render()
        |> then(&Regex.scan(~r/<li/, &1))
        |> length()
  end

  test "shows no upcoming dividends when none are expected", %{conn: conn, scope: scope} do
    holding_fixture(scope, 10)

    {:ok, lv, _html} = live(conn, ~p"/depot")

    refute has_element?(lv, "#upcoming-dividends")
  end

  describe "Depots" do
    # 240 € on the reference account since last year, 10 shares delivered yesterday at 100 €,
    # 102 € today: the securities are worth 1,020 €, +2,0 % on 1,000 €.
    setup %{scope: scope} do
      account = account_fixture(scope, %{name: "Konto Langfristig"})

      transaction_fixture(scope, Date.shift(today(), year: -1),
        type: :deposit,
        account_id: account.id,
        amount: money(240)
      )

      portfolio =
        portfolio_fixture(scope, %{name: "Langfristig", reference_account_id: account.id})

      deliver(scope, portfolio, 10, money(1_000))
      %{portfolio: portfolio}
    end

    defp deliver(scope, portfolio, count, amount) do
      security =
        security_fixture(quote_feed: :manual, latest_date: today(), latest_close: price(102))

      price_fixture(security, Date.add(today(), -1), price(100), :pp)

      transaction_fixture(scope, Date.add(today(), -1),
        type: :inbound_delivery,
        portfolio_id: portfolio.id,
        security_id: security.id,
        shares: shares(count),
        amount: amount
      )
    end

    test "lists each portfolio with its securities' value and TTWROR since 1 January", ctx do
      {:ok, lv, _html} = live(ctx.conn, ~p"/depot")

      row = lv |> element("#portfolio-#{ctx.portfolio.id}") |> render()

      assert row =~ "Langfristig"
      assert row =~ "1\u00A0Wertpapier\u2060\u00A0· Konto\u00A0240,00\u00A0€"
      assert row =~ "1.020,00\u00A0€"

      assert lv
             |> element(
               "#portfolio-#{ctx.portfolio.id} [class~='max-md:hidden'] .text-success-ink"
             )
             |> render() =~
               "+2,0\u00A0% YTD"
    end

    test "shows a portfolio without shares as cash only and hides retired ones once empty", ctx do
      cash = portfolio_fixture(ctx.scope, %{name: "Sparplan"})
      retired = portfolio_fixture(ctx.scope, %{name: "Alt", retired: true})
      empty = portfolio_fixture(ctx.scope, %{name: "Leer", retired: true})
      deliver(ctx.scope, retired, 1, money(100))

      {:ok, lv, _html} = live(ctx.conn, ~p"/depot")

      assert lv |> element("#portfolio-#{cash.id}") |> render() =~ "nur Cash"
      assert lv |> element("#portfolio-#{cash.id}") |> render() =~ "keine\u00A0Wertpapiere"
      assert has_element?(lv, "#portfolio-#{retired.id}", "102,00\u00A0€")
      refute has_element?(lv, "#portfolio-#{empty.id}")
    end

    test "leaves out a retired reference account once it is empty, as the sidebar does", ctx do
      account = account_fixture(ctx.scope, %{name: "Konto Alt", retired: true})

      portfolio =
        portfolio_fixture(ctx.scope, %{name: "Alt", reference_account_id: account.id})

      deliver(ctx.scope, portfolio, 1, money(100))

      {:ok, lv, _html} = live(ctx.conn, ~p"/depot")

      row = lv |> element("#portfolio-#{portfolio.id}") |> render()

      assert row =~ "1\u00A0Wertpapier"
      refute row =~ "Konto"
    end
  end
end
