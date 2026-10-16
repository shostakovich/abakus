defmodule AbakusWeb.Depot.SecurityLiveTest do
  use AbakusWeb.ConnCase

  import Phoenix.LiveViewTest
  import Abakus.Depot.{PortfoliosFixtures, SecuritiesFixtures}
  import Abakus.UsersFixtures

  alias Abakus.Depot.{ExchangeRates, FakeSymbolSource}
  alias Abakus.Depot.Portfolios.TransactionUnit
  alias Abakus.LocalTime
  alias Abakus.Repo
  alias AbakusWeb.Depot.Format

  setup :register_and_log_in_user

  setup %{scope: scope} do
    portfolio_fixture(scope)
    :ok
  end

  defp today, do: LocalTime.today()

  # Closes of 90 € two years ago and 100 € yesterday, quoted at 102 € today.
  defp security_fixture_with_prices do
    security =
      security_fixture(
        quote_feed: :manual,
        isin: "IE00B3RBWM25",
        wkn: "A1JX52",
        latest_date: today(),
        latest_close: price(102)
      )

    price_fixture(security, Date.shift(today(), year: -2), price(90), :pp)
    price_fixture(security, Date.add(today(), -1), price(100), :pp)
    security
  end

  defp trade(scope, type, portfolio, security, date, count, amount) do
    transaction_fixture(scope, date,
      type: type,
      portfolio_id: portfolio.id,
      security_id: security.id,
      shares: shares(count),
      amount: money(amount)
    )
  end

  describe "a security" do
    setup %{scope: scope} do
      security = security_fixture_with_prices()
      portfolio = portfolio_fixture(scope)
      trade(scope, :buy, portfolio, security, Date.add(today(), -30), 10, 950)
      trade(scope, :sell, portfolio, security, Date.add(today(), -10), 2, 196)
      trade(scope, :inbound_delivery, portfolio, security, Date.shift(today(), year: -2), 1, 90)
      other = user_scope_fixture()
      trade(other, :buy, portfolio_fixture(other), security, Date.add(today(), -20), 7, 700)

      %{security: security, portfolio: portfolio}
    end

    test "shows its price with the change since yesterday", %{conn: conn, security: security} do
      {:ok, lv, _html} = live(conn, ~p"/depot/securities/#{security}")

      assert page_title(lv) =~ "Vanguard FTSE All-World"
      assert has_element?(lv, "h1", "Vanguard FTSE All-World")
      assert has_element?(lv, "header", "IE00B3RBWM25\u2060\u00A0· WKN A1JX52\u2060\u00A0· EUR")
      assert lv |> element("#price") |> render() =~ "102,00\u00A0€"

      assert lv |> element("#price .text-success-ink") |> render() =~
               "+2,00\u00A0€ (+2,00\u00A0%) heute"
    end

    test "charts a year of prices with the user's purchases and sales", ctx do
      {:ok, lv, _html} = live(ctx.conn, ~p"/depot/securities/#{ctx.security}")

      assert has_element?(lv, "#period a[aria-current]", "1\u00A0J")
      assert_push_event(lv, "price-chart", chart)
      assert chart.currency == "€"
      assert chart.dates == [Date.add(today(), -1), today()]
      assert chart.prices == [price(100), price(102)]

      assert chart.trades == [
               %{date: Date.add(today(), -30), type: :buy, shares: shares(10), price: price(95)},
               %{date: Date.add(today(), -10), type: :sell, shares: shares(2), price: price(98)}
             ]

      assert has_element?(lv, "#price-chart-legend", "Kauf")
    end

    test "keeps the period in the URL, so that it survives a reload", ctx do
      {:ok, lv, _html} = live(ctx.conn, ~p"/depot/securities/#{ctx.security}")
      assert_push_event(lv, "price-chart", _one_year)

      lv |> element("#period a", "5\u00A0J") |> render_click()

      assert_patch(lv, ~p"/depot/securities/#{ctx.security}?period=5y")
      assert_push_event(lv, "price-chart", %{dates: [first | _], trades: [delivery | _]})
      assert first == Date.shift(today(), year: -2)
      assert delivery.type == :inbound_delivery

      {:ok, lv, _html} = live(ctx.conn, ~p"/depot/securities/#{ctx.security}?period=5y")

      assert has_element?(lv, "#period a[aria-current]", "5\u00A0J")
      assert_push_event(lv, "price-chart", %{dates: [^first | _]})
    end

    test "shows the holding of the user", ctx do
      {:ok, lv, _html} = live(ctx.conn, ~p"/depot/securities/#{ctx.security}")

      assert texts(lv, "#holding dt, #holding dd") == [
               "Stück",
               "9",
               "Wert",
               "918,00\u00A0€",
               "Einstand",
               "855,00\u00A0€",
               "Gewinn",
               "+63,00\u00A0€ +7,4\u00A0%"
             ]

      refute has_element?(lv, "#holding-portfolios")
    end

    test "shows the holding per portfolio when it is in several", ctx do
      pension = portfolio_fixture(ctx.scope, %{name: "Altersvorsorge"})
      trade(ctx.scope, :buy, pension, ctx.security, Date.add(today(), -5), 1, 99)

      {:ok, lv, _html} = live(ctx.conn, ~p"/depot/securities/#{ctx.security}")

      assert texts(lv, "#holding dd") |> hd() == "10"

      assert portfolio_texts(lv, pension) ==
               ["Altersvorsorge", "1 Stück", "102,00\u00A0€", "+3,00\u00A0€"]

      assert portfolio_texts(lv, ctx.portfolio) ==
               ["Langfristig", "9 Stück", "918,00\u00A0€", "+63,00\u00A0€"]

      assert has_element?(
               lv,
               "#holding-portfolios a:first-of-type[href='/depot/holdings?portfolio=#{pension.id}']"
             )
    end

    test "updates when new prices arrive", %{conn: conn, security: security} do
      {:ok, lv, _html} = live(conn, ~p"/depot/securities/#{security}")
      assert_push_event(lv, "price-chart", _before)

      Repo.update!(Ecto.Changeset.change(security, latest_close: price(110)))
      send(lv.pid, :market_data_updated)

      assert lv |> element("#price") |> render() =~ "110,00\u00A0€"
      assert_push_event(lv, "price-chart", %{prices: [_yesterday, today]})
      assert today == price(110)
    end

    test "marks the holdings in the navigation", %{conn: conn, security: security} do
      {:ok, lv, _html} = live(conn, ~p"/depot/securities/#{security}")

      assert has_element?(lv, sidebar_link("/depot/holdings") <> "[aria-current=page]")
      assert has_element?(lv, "main a[href='/depot/holdings']", "Bestand")
    end
  end

  describe "distributions" do
    setup %{scope: scope} do
      %{security: security_fixture_with_prices(), account: account_fixture(scope)}
    end

    test "lists per payment date the gross amount per share of the user's dividends", ctx do
      pension = account_fixture(ctx.scope, %{name: "Altersvorsorge"})
      paid = Date.add(today(), -100)
      tax = %TransactionUnit{type: :tax, amount: money(3), currency: "EUR"}
      dividend(ctx.scope, ctx.account, ctx.security, paid, 10, 15, units: [tax])
      dividend(ctx.scope, pension, ctx.security, paid, 2, 3.6)

      dividend(ctx.scope, ctx.account, ctx.security, Date.add(today(), -10), 8, 12,
        ex_date: NaiveDateTime.new!(Date.add(today(), -20), ~T[00:00:00])
      )

      other = user_scope_fixture()
      dividend(other, account_fixture(other), ctx.security, Date.add(today(), -10), 7, 70)

      {:ok, lv, _html} = live(ctx.conn, ~p"/depot/securities/#{ctx.security}")

      assert texts(lv, "#distributions th") ==
               ["Zahltag", "Ex-Tag", "je Anteil", "Stück", "Brutto"]

      assert cells(lv, "#distributions tbody tr", "td") == [
               [day(-10), short_day(-20), "1,50\u00A0€", "8", "12,00\u00A0€"],
               [day(-100), "–", "1,80\u00A0€", "12", "21,60\u00A0€"]
             ]

      assert has_element?(lv, "#distributions-total", "33,60\u00A0€")
    end

    test "gives the amount per share of a security in dollars in dollars", ctx do
      security = security_fixture(currency: "USD", quote_feed: :manual)

      gross = %TransactionUnit{
        type: :gross_value,
        amount: money(4.29),
        currency: "EUR",
        fx_amount: money(5),
        fx_currency: "USD",
        fx_rate: Decimal.new("0.858")
      }

      dividend(ctx.scope, ctx.account, security, Date.add(today(), -3), 10, 4.29, units: [gross])

      {:ok, lv, _html} = live(ctx.conn, ~p"/depot/securities/#{security}")

      assert cells(lv, "#distributions tbody tr", "td") ==
               [[day(-3), "0,50\u00A0USD", "10", "4,29\u00A0€"]]
    end

    test "shows a dividend booked without shares without an amount per share", ctx do
      dividend(ctx.scope, ctx.account, ctx.security, Date.add(today(), -3), 10, 15)
      dividend(ctx.scope, ctx.account, ctx.security, Date.add(today(), -5), 0, 5, shares: nil)

      {:ok, lv, _html} = live(ctx.conn, ~p"/depot/securities/#{ctx.security}")

      assert cells(lv, "#distributions tbody tr", "td") == [
               [day(-3), "1,50\u00A0€", "10", "15,00\u00A0€"],
               [day(-5), "–", "–", "5,00\u00A0€"]
             ]
    end

    test "shows the eight newest until all are asked for", ctx do
      for month <- 1..10,
          do:
            dividend(
              ctx.scope,
              ctx.account,
              ctx.security,
              Date.shift(today(), month: -month),
              1,
              1
            )

      {:ok, lv, _html} = live(ctx.conn, ~p"/depot/securities/#{ctx.security}")

      assert lv |> query("#distributions tbody tr:not([hidden])") |> Enum.count() == 8
      assert lv |> query("#distributions tbody tr[hidden]") |> Enum.count() == 2
      assert has_element?(lv, "#distributions-all", "Alle 10 anzeigen")
    end

    test "says so when no dividend is booked", ctx do
      {:ok, lv, _html} = live(ctx.conn, ~p"/depot/securities/#{ctx.security}")

      assert has_element?(lv, "#distributions", "Keine Ausschüttungen gebucht")
      refute has_element?(lv, "#distributions table")
    end
  end

  describe "Nächste Zahlungen" do
    setup %{scope: scope} do
      security = security_fixture_with_prices()
      deliver(scope, portfolio_fixture(scope), security, 100)
      %{security: security}
    end

    test "lists its announced and forecast dividends above its distributions", ctx do
      announced = Date.add(today(), 1)
      forecast = today() |> Date.beginning_of_month() |> Date.shift(month: 2) |> Date.add(14)
      divvy_diary_dividend_fixture(ctx.security, announced, announced, 0.5)

      divvy_diary_dividend_fixture(
        ctx.security,
        nil,
        Date.shift(forecast, year: -1),
        1,
        "USD"
      )

      ExchangeRates.store([{"USD", today(), Decimal.new("1.25")}])
      other = user_scope_fixture()
      deliver(other, portfolio_fixture(other), ctx.security, 1_000)
      dividend(other, account_fixture(other), ctx.security, Date.add(today(), -3), 1_000, 500)

      {:ok, lv, _html} = live(ctx.conn, ~p"/depot/securities/#{ctx.security}")

      assert texts(lv, "#upcoming-payments thead th") ==
               ["Zahltag", "Ex-Tag", "Art", "je Anteil", "Stück", "Brutto"]

      assert cells(lv, "#upcoming-payments tbody tr", "td") == [
               [
                 "#{day(1)} 100\u00A0Stück × 0,50\u00A0€",
                 short_day(1),
                 "angekündigt",
                 "0,50\u00A0€",
                 "100",
                 "50,00\u00A0€"
               ],
               [
                 "#{Format.date(forecast)} 100\u00A0Stück × ~1,00\u00A0USD",
                 "–",
                 "Prognose",
                 "~1,00\u00A0USD",
                 "100",
                 "~80,00\u00A0€"
               ]
             ]

      html = render(lv)

      assert :binary.match(html, "upcoming-payments") <
               :binary.match(html, "id=\"distributions\"")
    end

    test "is left out when no dividend is expected", ctx do
      {:ok, lv, _html} = live(ctx.conn, ~p"/depot/securities/#{ctx.security}")

      refute has_element?(lv, "#upcoming-payments")
    end
  end

  describe "profile" do
    test "shows every attribute set on the security under the name of its type", ctx do
      attribute_type_fixture("logo", "Logo", "ImageConverter", "Account")
      attribute_type_fixture("ter", "Total Expense Ratio (TER)", "PercentConverter")
      attribute_type_fixture("aum", "Assets under Management", "AmountPlainConverter")
      # PP's English default name for its built-in vendor attribute reads in German.
      attribute_type_fixture("vendor", "Vendor", "StringConverter")
      attribute_type_fixture("index", "Index", "StringConverter")
      attribute_type_fixture("launch", "Auflage", "DateConverter")
      attribute_type_fixture("fee", "Kaufgebühr", "PercentConverter")

      security =
        security_fixture_with_prices()
        |> Ecto.Changeset.change(
          attributes: %{
            "ter" => 0.0022,
            "aum" => 1_780_000_000_000,
            "vendor" => "Vanguard",
            "index" => "FTSE All-World",
            "launch" => Date.diff(~D[2012-05-22], ~D[1970-01-01]),
            "logo" => "data:image/png;base64,AAAA",
            "unknown" => "ohne Typ"
          }
        )
        |> Repo.update!()

      deliver(ctx.scope, portfolio_fixture(ctx.scope), security, 100)

      {:ok, lv, _html} = live(ctx.conn, ~p"/depot/securities/#{security}")

      assert texts(lv, "#profile dt, #profile dd") == [
               "TER",
               "0,22\u00A0%\u2060\u00A0· 22\u00A0€ im Jahr",
               "Fondsgröße",
               "17,8\u00A0Mrd.\u00A0€",
               "Anbieter",
               "Vanguard",
               "Index",
               "FTSE All-World",
               "Auflage",
               "22.05.2012"
             ]
    end

    test "links a bookmark as a styled link", ctx do
      attribute_type_fixture("factsheet", "Factsheet", "BookmarkConverter")

      security =
        security_fixture_with_prices()
        |> Ecto.Changeset.change(
          attributes: %{"factsheet" => "[Factsheet](https://example.com/fs.pdf)"}
        )
        |> Repo.update!()

      deliver(ctx.scope, portfolio_fixture(ctx.scope), security, 100)

      {:ok, lv, _html} = live(ctx.conn, ~p"/depot/securities/#{security}")

      assert has_element?(
               lv,
               ~s(#profile dd a.link[href="https://example.com/fs.pdf"][target=_blank]),
               "Factsheet"
             )
    end

    test "says so when no attribute is set", %{conn: conn} do
      security = security_fixture_with_prices()

      {:ok, lv, _html} = live(conn, ~p"/depot/securities/#{security}")

      assert has_element?(lv, "#profile", "Keine Angaben aus Portfolio Performance")
      refute has_element?(lv, "#profile dl")
    end
  end

  describe "composition" do
    setup do
      FakeSymbolSource.stub()
      %{security: security_fixture_with_prices()}
    end

    test "shows the regions and sectors of the security as the holdings do", ctx do
      composition_fixture(ctx.security, %{"US" => 0.6, "JP" => 0.25, "BR" => 0.15}, %{
        "Information Technology" => 0.7,
        "Energy" => 0.3
      })

      {:ok, lv, _html} = live(ctx.conn, ~p"/depot/securities/#{ctx.security}")

      assert lines(lv, "#composition-rows li", "span") ==
               ["USA 60,0\u00A0%", "Japan 25,0\u00A0%", "Schwellenländer 15,0\u00A0%"]

      assert has_element?(lv, "#composition", "DivvyDiary, Stand 08.10.2026")

      lv |> element("#composition nav a", "Sektoren") |> render_click()
      url = assert_patch(lv, ~p"/depot/securities/#{ctx.security}?composition=sectors")

      assert lines(lv, "#composition-rows li", "span") == [
               "Technologie 70,0\u00A0%",
               "Energie 30,0\u00A0%"
             ]

      lv |> element("#period a", "5\u00A0J") |> render_click()
      assert_patch(lv, ~p"/depot/securities/#{ctx.security}?composition=sectors&period=5y")

      {:ok, lv, _html} = live(ctx.conn, url)

      assert has_element?(lv, "#composition nav a[aria-current]", "Sektoren")
      assert has_element?(lv, "#period a[href$='?composition=sectors&period=max']", "Max")
    end

    test "says so when DivvyDiary has none", ctx do
      {:ok, lv, _html} = live(ctx.conn, ~p"/depot/securities/#{ctx.security}")

      assert has_element?(lv, "#composition", "keine Länder und Sektoren")
      refute has_element?(lv, "#composition nav")
    end

    test "shows a hint without an API key", ctx do
      Application.delete_env(:abakus, FakeSymbolSource)
      composition_fixture(ctx.security, %{"US" => 1})

      {:ok, lv, _html} = live(ctx.conn, ~p"/depot/securities/#{ctx.security}")

      assert has_element?(lv, "#composition", "DIVVYDIARY_API_KEY")
      refute has_element?(lv, "#composition-rows")
    end
  end

  describe "data sources" do
    test "name the quote feed, the composition and the link to the settings", ctx do
      FakeSymbolSource.stub()
      fetched = DateTime.add(DateTime.utc_now(), -1, :minute)

      # Checked just now, so that opening the page does not fetch its quote again.
      security =
        security_fixture(isin: "IE00B3RBWM25", fetched_at: fetched, checked_at: fetched)

      composition_fixture(security, %{"US" => 1})

      {:ok, lv, _html} = live(ctx.conn, ~p"/depot/securities/#{security}")

      assert lines(lv, "#sources dl > div", "dt, p") == [
               "Kurse Yahoo\u2060\u00A0· VGWL.DE abgerufen #{Format.datetime(fetched)}",
               "Länder und Sektoren DivvyDiary Stand 08.10.2026"
             ]

      assert has_element?(
               lv,
               "#sources a[href='/depot/securities#security-#{security.id}']",
               "Kursquelle ändern"
             )
    end

    test "name the ECB rate for a security in another currency", ctx do
      ExchangeRates.store([{"USD", ~D[2026-10-08], Decimal.new("1.1652")}])
      security = security_fixture(currency: "USD", quote_feed: :manual)

      {:ok, lv, _html} = live(ctx.conn, ~p"/depot/securities/#{security}")

      assert lines(lv, "#sources dl > div", "dt, p") == [
               "Kurse Portfolio Performance nur aus dem PP-Import",
               "Wechselkurs USD EZB\u2060\u00A0· 1,1652 Stand 08.10.2026",
               "Länder und Sektoren DivvyDiary ohne API-Key"
             ]
    end
  end

  test "says so for a security the user does not hold", %{conn: conn} do
    security = security_fixture_with_prices()

    {:ok, lv, _html} = live(conn, ~p"/depot/securities/#{security}")

    assert has_element?(lv, "#holding", "Nicht im Bestand")
    refute has_element?(lv, "#price-chart-legend")
  end

  test "shows a change in price too small to show without a sign or colour", %{conn: conn} do
    security = security_fixture_with_prices()
    Repo.update!(Ecto.Changeset.change(security, latest_close: price(100) + 150))

    {:ok, lv, _html} = live(conn, ~p"/depot/securities/#{security}")

    assert lv |> element("#price [class~=\"text-base-content/70\"]") |> render() =~
             ~r/>\s*0,00\s€ \(0,00\s%\) heute/u
  end

  test "says so when there is no price in the period", %{conn: conn} do
    security = security_fixture(quote_feed: :manual)
    price_fixture(security, Date.shift(today(), year: -3), price(50), :pp)

    {:ok, lv, _html} = live(conn, ~p"/depot/securities/#{security}")

    assert has_element?(lv, "#price-chart-empty", "Keine Kurse")
    assert_push_event(lv, "price-chart", %{dates: []})

    lv |> element("#period a", "Max") |> render_click()

    refute has_element?(lv, "#price-chart-empty")
  end

  test "shows that an unknown security does not exist", %{conn: conn} do
    for id <- [System.unique_integer([:positive]), "unknown", "0", "9223372036854775808"] do
      {:ok, lv, _html} = live(conn, ~p"/depot/securities/#{id}")

      assert has_element?(lv, "h1", "Wertpapier nicht gefunden")
      assert has_element?(lv, "main a[href='/depot/holdings']")
      refute has_element?(lv, "#period")
    end
  end

  defp dividend(scope, account, security, date, count, gross, attrs \\ []) do
    transaction_fixture(
      scope,
      date,
      [
        type: :dividend,
        account_id: account.id,
        security_id: security.id,
        shares: shares(count),
        amount: money(gross)
      ] ++ attrs
    )
  end

  defp deliver(scope, portfolio, security, count) do
    transaction_fixture(scope, Date.add(today(), -5),
      type: :inbound_delivery,
      portfolio_id: portfolio.id,
      security_id: security.id,
      shares: shares(count)
    )
  end

  defp day(days), do: today() |> Date.add(days) |> Format.date()
  defp short_day(days), do: today() |> Date.add(days) |> Calendar.strftime("%d.%m.")

  defp portfolio_texts(lv, portfolio),
    do: texts(lv, "#holding-#{portfolio.id} :is(a, p, [class~='max-md:hidden'] data)")

  defp texts(lv, selector), do: lv |> query(selector) |> Enum.map(&text/1)

  # The texts of the cells of each row.
  defp cells(lv, rows, cell) do
    for row <- query(lv, rows), do: row |> LazyHTML.query(cell) |> Enum.map(&text/1)
  end

  # The texts of the parts of each row, joined.
  defp lines(lv, rows, parts), do: lv |> cells(rows, parts) |> Enum.map(&Enum.join(&1, " "))

  defp query(lv, selector),
    do: lv |> render() |> LazyHTML.from_fragment() |> LazyHTML.query(selector)

  defp text(node), do: node |> LazyHTML.text() |> String.split() |> Enum.join(" ")
end
