defmodule AbakusWeb.Depot.HoldingsLiveTest do
  use AbakusWeb.ConnCase

  import Phoenix.LiveViewTest
  import Abakus.Depot.{PortfoliosFixtures, SecuritiesFixtures, TaxonomiesFixtures}

  alias Abakus.Depot.FakeSymbolSource
  alias Abakus.Depot.Portfolios
  alias Abakus.Depot.Portfolios.TransactionUnit
  alias Abakus.Ledger.Account
  alias Abakus.LocalTime
  alias Abakus.Repo

  setup :register_and_log_in_user

  defp today, do: LocalTime.today()

  defp security(close, attrs \\ []) do
    security = security_fixture([quote_feed: :manual, isin: "IE00B3RBWM25"] ++ attrs)

    price_fixture(security, Date.add(today(), -1), price(close), :manual)
    security
  end

  defp deliver(scope, portfolio, security, count, amount) do
    transaction_fixture(scope, Date.add(today(), -1),
      type: :inbound_delivery,
      portfolio_id: portfolio.id,
      security_id: security.id,
      shares: shares(count),
      amount: money(amount)
    )
  end

  defp deposit(scope, account, amount) do
    transaction_fixture(scope, Date.add(today(), -1),
      type: :deposit,
      account_id: account.id,
      amount: money(amount)
    )
  end

  test "values the remaining shares after a partial sale at their FIFO purchase value", ctx do
    account = account_fixture(ctx.scope)
    portfolio = portfolio_fixture(ctx.scope, %{reference_account_id: account.id})
    security = security(130)
    trade = [portfolio_id: portfolio.id, account_id: account.id, security_id: security.id]

    transaction_fixture(
      ctx.scope,
      Date.add(today(), -30),
      [type: :buy, shares: shares(10), amount: money(1_000)] ++ trade
    )

    transaction_fixture(
      ctx.scope,
      Date.add(today(), -20),
      [
        type: :buy,
        shares: shares(10),
        amount: money(1_210),
        units: [%TransactionUnit{type: :fee, amount: money(10)}]
      ] ++ trade
    )

    transaction_fixture(
      ctx.scope,
      Date.add(today(), -10),
      [type: :sell, shares: shares(15), amount: money(1_800)] ++ trade
    )

    {:ok, lv, _html} = live(ctx.conn, ~p"/depot/holdings")

    row = lv |> element("#holding-#{portfolio.id}-#{security.id}") |> render()

    assert row =~ "Vanguard FTSE All-World"
    assert row =~ "IE00B3RBWM25"
    assert row =~ ~r/>\s*5\s*</
    assert row =~ "130,00\u00A0€"
    assert row =~ "650,00\u00A0€"
    assert row =~ "605,00\u00A0€"
    assert row =~ "+45,00\u00A0€"
    assert row =~ "+7,4\u00A0%"
    # No position pays a dividend, so there is no yield column.
    refute has_element?(lv, "thead th", "Div.-Rendite")
  end

  test "shows each holding's dividend yield and that of all, gross over the next 12 months",
       ctx do
    paying = security(100, name: "Ausschüttend")
    accumulating = security(50, name: "Thesaurierend")
    portfolio = portfolio_fixture(ctx.scope)
    other = portfolio_fixture(ctx.scope, %{name: "Sparplan"})
    deliver(ctx.scope, portfolio, paying, 30, 3_000)
    deliver(ctx.scope, other, paying, 10, 1_000)
    deliver(ctx.scope, portfolio, accumulating, 40, 2_000)
    deposit(ctx.scope, account_fixture(ctx.scope), 500)
    divvy_diary_dividend_fixture(paying, nil, Date.add(today(), 10), 2)
    stranger = Abakus.UsersFixtures.user_scope_fixture()
    deliver(stranger, portfolio_fixture(stranger), paying, 1_000, 100_000)

    transaction_fixture(stranger, Date.add(today(), -100),
      type: :dividend,
      account_id: account_fixture(stranger).id,
      security_id: paying.id,
      shares: shares(1_000),
      amount: money(500)
    )

    {:ok, lv, _html} = live(ctx.conn, ~p"/depot/holdings")

    assert has_element?(lv, "thead th", "Div.-Rendite")

    assert lv |> element("#holding-#{portfolio.id}-#{paying.id} td:last-child") |> render() =~
             "2,0\u00A0%"

    assert lv |> element("#holding-#{other.id}-#{paying.id} td:last-child") |> render() =~
             "2,0\u00A0%"

    assert lv |> element("#holding-#{portfolio.id}-#{accumulating.id} td:last-child") |> render() =~
             "–"

    assert lv |> element("tfoot:has(#holdings-total) td:last-child") |> render() =~ "1,3\u00A0%"

    {:ok, lv, _html} = live(ctx.conn, ~p"/depot/holdings?portfolio=#{other.id}")

    assert lv |> element("tfoot:has(#holdings-total) td:last-child") |> render() =~ "2,0\u00A0%"
  end

  test "shows the costs of the held funds, weighted by value", ctx do
    portfolio = portfolio_fixture(ctx.scope)

    world =
      security(80, name: "All-World", attributes: %{"ter" => 0.002, "aum" => 1_780_000_000_000})

    em = security(20, name: "Emerging Markets", attributes: %{"ter" => 0.005})
    unknown = security(10, name: "Ohne TER")
    deliver(ctx.scope, portfolio, world, 100, 8_000)
    deliver(ctx.scope, portfolio, em, 100, 2_000)
    deliver(ctx.scope, portfolio, unknown, 100, 1_000)

    {:ok, lv, _html} = live(ctx.conn, ~p"/depot/holdings")

    assert has_element?(lv, "#costs", "gewichtet 0,26\u00A0%")

    assert cells(lv, "#cost-#{world.id}") ==
             [
               "All-World Fondsgröße 17,8\u00A0Mrd.\u00A0€",
               "0,20\u00A0%",
               "17,8\u00A0Mrd.\u00A0€",
               "16\u00A0€"
             ]

    assert cells(lv, "#cost-#{em.id}") == ["Emerging Markets", "0,50\u00A0%", "–", "10\u00A0€"]
    assert cells(lv, "#cost-#{unknown.id}") == ["Ohne TER", "–", "–", "–"]
    assert cells(lv, "#costs tfoot tr") == ["Gesamt", "0,26\u00A0%", "", "26\u00A0€"]
    assert has_element?(lv, "#costs", "Wertpapiere ohne TER")
  end

  test "links the securities of the holdings and the costs to their page", ctx do
    portfolio = portfolio_fixture(ctx.scope)
    security = security(100, attributes: %{"ter" => 0.002})
    deliver(ctx.scope, portfolio, security, 1, 100)

    {:ok, lv, _html} = live(ctx.conn, ~p"/depot/holdings")

    link = "a[href='#{~p"/depot/securities/#{security}"}']"
    assert has_element?(lv, "#holding-#{portfolio.id}-#{security.id} #{link}", security.name)
    assert has_element?(lv, "#cost-#{security.id} #{link}", security.name)
  end

  test "shows no costs without securities", ctx do
    account = account_fixture(ctx.scope)
    portfolio_fixture(ctx.scope, reference_account_id: account.id)
    deposit(ctx.scope, account, 100)

    {:ok, lv, _html} = live(ctx.conn, ~p"/depot/holdings")

    refute has_element?(lv, "#costs")
  end

  defp cells(lv, selector), do: texts(lv, "#{selector} > :is(th, td)")

  defp texts(lv, selector) do
    lv
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.query(selector)
    |> Enum.map(&(&1 |> LazyHTML.text() |> String.split() |> Enum.join(" ")))
  end

  defp progress(html) do
    [_, value] = Regex.run(~r/<progress[^>]* value="([\d.]+)"/, html)
    [_, max] = Regex.run(~r/<progress[^>]* max="([\d.]+)"/, html)
    {value, max}
  end

  # Each row of the allocation as "label share".
  defp allocation(lv) do
    lv
    |> texts("#allocation-rows > li > div > div:first-child > span")
    |> Enum.chunk_every(2)
    |> Enum.map(&Enum.join(&1, " "))
  end

  describe "allocation" do
    setup do
      FakeSymbolSource.stub()
    end

    test "gives the regions from the composition of the funds; accounts do not count", ctx do
      portfolio = portfolio_fixture(ctx.scope)
      world = security(60, name: "Welt")
      brazil = security(40, name: "Brasilien")
      composition_fixture(world, %{"US" => 0.6, "JP" => 0.4})
      composition_fixture(brazil, %{"BR" => 1})
      deliver(ctx.scope, portfolio, world, 100, 6_000)
      deliver(ctx.scope, portfolio, brazil, 100, 4_000)
      deposit(ctx.scope, account_fixture(ctx.scope), 1_000)

      {:ok, lv, _html} = live(ctx.conn, ~p"/depot/holdings")

      assert has_element?(lv, "#allocation nav a[aria-current]", "Regionen")

      assert allocation(lv) == [
               "Schwellenländer 40,0 %",
               "USA 36,0 %",
               "Japan 24,0 %"
             ]

      assert has_element?(lv, "#allocation", "Stand 08.10.2026")
      assert has_element?(lv, "#allocation", "Konten zählen nicht mit")

      # Each bar's value is its true share; the largest fills the bar.
      assert lv |> element("#allocation-rows > li:nth-child(1)") |> render() |> progress() ==
               {"40.0", "40.0"}

      assert lv |> element("#allocation-rows > li:nth-child(2)") |> render() |> progress() ==
               {"36.0", "40.0"}
    end

    test "counts a fund without composition as „Ohne Angabe“", ctx do
      portfolio = portfolio_fixture(ctx.scope)
      us = security(90, name: "USA")
      composition_fixture(us, %{"US" => 1})
      deliver(ctx.scope, portfolio, us, 100, 9_000)
      deliver(ctx.scope, portfolio, security(10, name: "Unbekannt"), 100, 1_000)

      {:ok, lv, _html} = live(ctx.conn, ~p"/depot/holdings")

      assert allocation(lv) == ["USA 90,0 %", "Ohne Angabe 10,0 %"]
      assert has_element?(lv, "#allocation", "ohne Länder- oder Sektordaten")
    end

    test "keeps the tab in the URL, so that it survives a reload", ctx do
      portfolio = portfolio_fixture(ctx.scope)
      fund = security(100, name: "Welt")

      composition_fixture(fund, %{"US" => 1}, %{
        "Information Technology" => 0.75,
        "Energy" => 0.25
      })

      deliver(ctx.scope, portfolio, fund, 10, 1_000)
      {:ok, lv, _html} = live(ctx.conn, ~p"/depot/holdings")

      lv |> element("#allocation nav a", "Sektoren") |> render_click()
      url = assert_patch(lv, ~p"/depot/holdings?allocation=sectors")

      {:ok, lv, _html} = live(ctx.conn, url)

      assert has_element?(lv, "#allocation nav a[aria-current]", "Sektoren")
      assert allocation(lv) == ["Technologie 75,0 %", "Energie 25,0 %"]

      lv |> element("#portfolio-menu a", "Langfristig") |> render_click()

      assert_patch(lv, ~p"/depot/holdings?allocation=sectors&portfolio=#{portfolio.id}")
      assert has_element?(lv, "#allocation nav a[aria-current]", "Sektoren")

      lv |> element("#allocation nav a", "Regionen") |> render_click()

      assert_patch(lv, ~p"/depot/holdings?portfolio=#{portfolio.id}")
      assert allocation(lv) == ["USA 100,0 %"]
    end

    test "shows a hint instead of regions and sectors without an API key", ctx do
      Application.delete_env(:abakus, FakeSymbolSource)
      portfolio = portfolio_fixture(ctx.scope)
      fund = security(100)
      composition_fixture(fund, %{"US" => 1})
      deliver(ctx.scope, portfolio, fund, 10, 1_000)

      for tab <- ["regions", "sectors"] do
        {:ok, lv, _html} = live(ctx.conn, ~p"/depot/holdings?allocation=#{tab}")

        assert allocation(lv) == []
        assert has_element?(lv, "#allocation", "DIVVYDIARY_API_KEY")
        refute has_element?(lv, "#allocation", "Stand")
      end
    end
  end

  describe "allocation by taxonomy" do
    setup %{scope: scope} do
      account = account_fixture(scope, %{name: "Tagesgeld"})
      deposit(scope, account, 2_000)
      portfolio = portfolio_fixture(scope, %{reference_account_id: account.id})
      world = security(70, name: "Welt")
      em = security(10, name: "Schwellenländer-ETF")
      deliver(scope, portfolio, world, 100, 7_000)
      deliver(scope, portfolio, em, 100, 1_000)

      {taxonomy, root} = taxonomy_fixture(scope, "Anlageklassen")
      equity = classification_fixture(root, "Aktien", 8_000, 0)
      assignment_fixture(classification_fixture(equity, "Industrieländer", 8_500), world)
      assignment_fixture(classification_fixture(equity, "Schwellenländer", 1_500), em)
      real_estate = classification_fixture(root, "Immobilien", 1_000, 1)
      risk_free = classification_fixture(root, "Risikofrei", 1_000, 2)
      assignment_fixture(risk_free, account)

      %{
        portfolio: portfolio,
        world: world,
        taxonomy: taxonomy,
        real_estate: real_estate,
        risk_free: risk_free
      }
    end

    # Each row as "name share Ziel target", with its deviation from the target.
    defp classifications(lv), do: texts(lv, "#allocation-rows > li")

    # {value, max, target marker} of a classification's bar, in percent of the bar.
    defp bar(lv, classification) do
      html = lv |> element("#classification-#{classification.id}") |> render()
      {value, max} = progress(html)
      [_, target] = Regex.run(~r/<rect[^>]* x="([\d.]+)%"/, html)
      {value, max, target}
    end

    test "compares the top-level classifications with their targets; accounts count", ctx do
      {:ok, lv, _html} = live(ctx.conn, ~p"/depot/holdings")

      lv |> element("#allocation nav a", "Anlageklassen") |> render_click()

      assert classifications(lv) == [
               "Aktien 80,0\u00A0% Ziel 80,0\u00A0%",
               "Immobilien 0,0\u00A0% Ziel 10,0\u00A0% unter Ziel",
               "Risikofrei 20,0\u00A0% Ziel 10,0\u00A0% über Ziel"
             ]

      assert has_element?(lv, "#classification-#{ctx.real_estate.id} .badge", "unter Ziel")
      assert has_element?(lv, "#classification-#{ctx.risk_free.id} .badge", "über Ziel")

      # Value is the true share; the largest share or target fills the bar; a 10 % target marks 12.5 % of 80 %.
      assert bar(lv, ctx.real_estate) == {"0.0", "80.0", "12.5"}
      assert bar(lv, ctx.risk_free) == {"20.0", "80.0", "12.5"}
      refute has_element?(lv, "#allocation", "Ohne Kategorie")
    end

    test "names the value in no classification „Ohne Kategorie“", ctx do
      deliver(ctx.scope, ctx.portfolio, security(20, name: "Gold"), 100, 2_000)

      {:ok, lv, _html} = live(ctx.conn, ~p"/depot/holdings?allocation=#{ctx.taxonomy.id}")

      assert ["Aktien 80,0\u00A0% Ziel 80,0\u00A0%" | _] = classifications(lv)

      assert has_element?(
               lv,
               "#allocation",
               "Ohne Kategorie: 2.000,00\u00A0€ (16,7\u00A0% des Werts)"
             )
    end

    test "shows odd targets as they are and keeps their marker on the bar", ctx do
      Repo.update!(Ecto.Changeset.change(ctx.real_estate, weight: -30_000))
      Repo.update!(Ecto.Changeset.change(ctx.risk_free, weight: 40_000))

      {:ok, lv, _html} = live(ctx.conn, ~p"/depot/holdings?allocation=#{ctx.taxonomy.id}")

      assert classifications(lv) == [
               "Aktien 80,0\u00A0% Ziel 80,0\u00A0%",
               "Immobilien 0,0\u00A0% Ziel −300,0\u00A0% über Ziel",
               "Risikofrei 20,0\u00A0% Ziel 400,0\u00A0% unter Ziel"
             ]

      assert bar(lv, ctx.real_estate) == {"0.0", "100.0", "0"}
      assert bar(lv, ctx.risk_free) == {"20.0", "100.0", "100"}
    end

    test "keeps the tab in the URL, so that it survives a reload and the switcher", ctx do
      {:ok, lv, _html} = live(ctx.conn, ~p"/depot/holdings")

      lv |> element("#allocation nav a", "Anlageklassen") |> render_click()
      url = assert_patch(lv, ~p"/depot/holdings?allocation=#{ctx.taxonomy.id}")

      {:ok, lv, _html} = live(ctx.conn, url)

      assert has_element?(lv, "#allocation nav a[aria-current]", "Anlageklassen")

      lv |> element("#portfolio-menu a", "Langfristig") |> render_click()

      assert_patch(
        lv,
        ~p"/depot/holdings?allocation=#{ctx.taxonomy.id}&portfolio=#{ctx.portfolio.id}"
      )

      assert has_element?(lv, "#allocation nav a[aria-current]", "Anlageklassen")
    end

    test "shows the regions for a portfolio without value in the taxonomy", ctx do
      other = portfolio_fixture(ctx.scope, %{name: "Spielgeld"})
      deliver(ctx.scope, other, security(50, name: "Einzelaktie"), 10, 500)
      {:ok, lv, _html} = live(ctx.conn, ~p"/depot/holdings?allocation=#{ctx.taxonomy.id}")

      lv |> element("#portfolio-menu a", "Spielgeld") |> render_click()

      assert_patch(lv, ~p"/depot/holdings?allocation=#{ctx.taxonomy.id}&portfolio=#{other.id}")
      assert has_element?(lv, "#allocation nav a[aria-current]", "Regionen")
      refute has_element?(lv, "#allocation nav a", "Anlageklassen")

      lv |> element("#portfolio-menu a", "Gesamt") |> render_click()

      assert_patch(lv, ~p"/depot/holdings?allocation=#{ctx.taxonomy.id}")
      assert has_element?(lv, "#allocation nav a[aria-current]", "Anlageklassen")
    end

    test "gives no tab to a taxonomy with nothing held, nor to another user's", ctx do
      {empty, root} = taxonomy_fixture(ctx.scope, "Branchen")
      assignment_fixture(classification_fixture(root, "Technologie", 10_000), security(1))

      {foreign, foreign_root} =
        taxonomy_fixture(Abakus.UsersFixtures.user_scope_fixture(), "Fremd")

      assignment_fixture(classification_fixture(foreign_root, "Alles", 10_000), ctx.world)

      for id <- [empty.id, foreign.id, "x"] do
        {:ok, lv, _html} = live(ctx.conn, ~p"/depot/holdings?allocation=#{id}")

        assert has_element?(lv, "#allocation nav a[aria-current]", "Regionen")
        assert has_element?(lv, "#allocation nav a", "Anlageklassen")
        refute has_element?(lv, "#allocation nav a", "Branchen")
        refute has_element?(lv, "#allocation nav a", "Fremd")
      end
    end
  end

  describe "a portfolio's cash beside a portfolio on a budget account" do
    setup %{scope: scope} do
      account = account_fixture(scope, %{name: "K"})
      deposit(scope, account, 50)
      giro = account_fixture(scope, %{name: "Giro", kind: :checking})
      a = portfolio_fixture(scope, %{name: "A", reference_account_id: account.id})
      b = portfolio_fixture(scope, %{name: "B", reference_account_id: giro.id})
      deliver(scope, b, security(100), 1, 100)
      %{account: account, a: a, b: b}
    end

    test "appears once, under its portfolio, while all are shown", ctx do
      {:ok, lv, _html} = live(ctx.conn, ~p"/depot/holdings")

      assert has_element?(lv, "#portfolio-menu summary", "Gesamt")
      assert has_element?(lv, "#portfolio-menu a[href$='=#{ctx.b.id}']", "B")
      assert has_element?(lv, "#holdings-portfolio-#{ctx.a.id} #account-#{ctx.account.id}", "K")
      refute has_element?(lv, "#holdings-portfolio-#{ctx.b.id} #account-#{ctx.account.id}")
      refute has_element?(lv, "#holdings-accounts")
      assert has_element?(lv, "tfoot:has(#holdings-total)", "150,00\u00A0€")
    end

    test "stays out of the other portfolio when that is selected", ctx do
      {:ok, lv, _html} = live(ctx.conn, ~p"/depot/holdings")

      lv |> element("#portfolio-menu a", "B") |> render_click()

      assert_patch(lv, ~p"/depot/holdings?portfolio=#{ctx.b.id}")
      assert has_element?(lv, "#portfolio-menu summary", "B")
      refute has_element?(lv, "#account-#{ctx.account.id}")
      refute has_element?(lv, "#holdings-portfolio-#{ctx.a.id}")
      assert has_element?(lv, "tfoot:has(#holdings-total)", "100,00\u00A0€")
    end

    test "keeps the selected portfolio in the URL, so that it survives a reload", ctx do
      {:ok, lv, _html} = live(ctx.conn, ~p"/depot/holdings")
      lv |> element("#portfolio-menu a", "B") |> render_click()
      url = assert_patch(lv)

      {:ok, lv, _html} = live(ctx.conn, url)

      assert has_element?(lv, "#portfolio-menu summary", "B")
      assert has_element?(lv, "#portfolio-menu a[aria-current]", "B")
      assert has_element?(lv, "#holdings-portfolio-#{ctx.b.id}")
      refute has_element?(lv, "#holdings-portfolio-#{ctx.a.id}")

      lv |> element("#portfolio-menu a", "Gesamt") |> render_click()

      assert_patch(lv, ~p"/depot/holdings")
      assert has_element?(lv, "#holdings-portfolio-#{ctx.a.id}")
    end
  end

  describe "a portfolio's cash" do
    setup %{scope: scope} do
      cash = account_fixture(scope, %{name: "Broker-Cash"})
      portfolio = portfolio_fixture(scope, %{name: "Broker", reference_account_id: cash.id})
      deposit(scope, cash, 2_100)
      deliver(scope, portfolio, security(90), 10, 900)
      %{portfolio: portfolio, cash: cash}
    end

    test "shows in the portfolio's Bestand as „davon Cash“", ctx do
      {:ok, lv, _html} = live(ctx.conn, ~p"/depot/holdings?portfolio=#{ctx.portfolio.id}")

      assert has_element?(lv, "header", "davon Cash\u00A02.100,00\u00A0€")
      assert lv |> element("#account-#{ctx.cash.id}") |> render() =~ "Cash"
      assert has_element?(lv, "tfoot:has(#holdings-total)", "3.000,00\u00A0€")
    end

    test "keeps what a purchase from it left as „davon Cash“", %{scope: scope, conn: conn} do
      {:ok, portfolio} =
        Portfolios.create_portfolio(scope, %{name: "Depot", account_name: "Cash"})

      deposit(
        scope,
        Repo.get!(Account, portfolio.reference_account_id),
        1_000
      )

      transaction_fixture(scope, Date.add(today(), -1),
        type: :buy,
        portfolio_id: portfolio.id,
        account_id: portfolio.reference_account_id,
        security_id: security(100).id,
        shares: shares(9),
        amount: money(900)
      )

      {:ok, lv, _html} = live(conn, ~p"/depot/holdings?portfolio=#{portfolio.id}")

      assert has_element?(lv, "header", "davon Cash\u00A0100,00\u00A0€")
      assert lv |> element("[id^=holding-#{portfolio.id}-]") |> render() =~ "900,00\u00A0€"
      assert has_element?(lv, "tfoot:has(#holdings-total)", "1.000,00\u00A0€")
    end

    test "appears under its portfolio while all are shown", ctx do
      {:ok, lv, _html} = live(ctx.conn, ~p"/depot/holdings")

      assert has_element?(lv, "#holdings-portfolio-#{ctx.portfolio.id} #account-#{ctx.cash.id}")
      refute has_element?(lv, "#holdings-accounts")
    end
  end

  test "groups the accounts of no portfolio as „Konten“", ctx do
    savings = account_fixture(ctx.scope, %{name: "Tagesgeld"})
    deposit(ctx.scope, savings, 1_000)
    portfolio = portfolio_fixture(ctx.scope)
    deliver(ctx.scope, portfolio, security(100), 10, 1_000)

    {:ok, lv, _html} = live(ctx.conn, ~p"/depot/holdings")

    assert has_element?(lv, "#holdings-accounts", "Konten")
    assert has_element?(lv, "#holdings-accounts #account-#{savings.id}", "Tagesgeld")

    assert lv |> element("#account-#{savings.id}") |> render() =~ "1.000,00\u00A0€"
    assert lv |> element("#account-#{savings.id}") |> render() =~ "50,0\u00A0%"

    lv |> element("#portfolio-menu a", "Langfristig") |> render_click()

    refute has_element?(lv, "#holdings-accounts")
    assert lv |> element("tfoot:has(#holdings-total)") |> render() =~ "50,0\u00A0%"
  end

  test "hides holdings without shares, and retired portfolios and accounts once empty", ctx do
    portfolio = portfolio_fixture(ctx.scope)
    sold = security(100, name: "Verkauft")
    deliver(ctx.scope, portfolio, sold, 1, 100)

    transaction_fixture(ctx.scope, today(),
      type: :outbound_delivery,
      portfolio_id: portfolio.id,
      security_id: sold.id,
      shares: shares(1)
    )

    retired = portfolio_fixture(ctx.scope, %{name: "Alt", retired: true})
    deliver(ctx.scope, retired, security(100), 1, 100)
    empty = portfolio_fixture(ctx.scope, %{name: "Leer", retired: true})
    closed = account_fixture(ctx.scope, %{name: "Geschlossen", closed: true})
    kept = account_fixture(ctx.scope, %{name: "Noch offen", closed: true})
    deposit(ctx.scope, kept, 1)

    {:ok, lv, _html} = live(ctx.conn, ~p"/depot/holdings")

    refute has_element?(lv, "#holding-#{portfolio.id}-#{sold.id}")
    assert has_element?(lv, "#holdings-portfolio-#{portfolio.id}", "Keine Wertpapiere")
    assert has_element?(lv, "#holdings-portfolio-#{retired.id}")
    assert has_element?(lv, "#portfolio-menu a", "Alt")
    refute has_element?(lv, "#holdings-portfolio-#{empty.id}")
    refute has_element?(lv, "#portfolio-menu a", "Leer")
    refute has_element?(lv, "#account-#{closed.id}")
    assert has_element?(lv, "#account-#{kept.id}")
  end

  test "shows all portfolios for a portfolio that is not the user's", ctx do
    portfolio = portfolio_fixture(ctx.scope)
    other = Abakus.UsersFixtures.user_scope_fixture()
    foreign = portfolio_fixture(other, %{name: "Fremd"})

    {:ok, lv, _html} = live(ctx.conn, ~p"/depot/holdings?portfolio=#{foreign.id}")

    assert has_element?(lv, "#portfolio-menu summary", "Gesamt")
    assert has_element?(lv, "#holdings-portfolio-#{portfolio.id}")
    refute render(lv) =~ "Fremd"
  end

  test "updates when new prices arrive", ctx do
    portfolio = portfolio_fixture(ctx.scope)
    security = security(100)
    deliver(ctx.scope, portfolio, security, 10, 1_000)
    {:ok, lv, _html} = live(ctx.conn, ~p"/depot/holdings")

    Repo.update!(Ecto.Changeset.change(security, latest_date: today(), latest_close: price(110)))
    send(lv.pid, :market_data_updated)

    assert lv |> element("#holding-#{portfolio.id}-#{security.id}") |> render() =~
             "1.100,00\u00A0€"
  end

  test "is reached from the overview's portfolios", ctx do
    portfolio = portfolio_fixture(ctx.scope)
    deliver(ctx.scope, portfolio, security(100), 1, 100)

    {:ok, lv, _html} = live(ctx.conn, ~p"/depot")

    assert {:ok, lv, _html} =
             lv
             |> element("#portfolio-#{portfolio.id} a")
             |> render_click()
             |> follow_redirect(ctx.conn, ~p"/depot/holdings?portfolio=#{portfolio.id}")

    assert has_element?(lv, "#portfolio-menu summary", "Langfristig")
  end

  test "is not shown to a visitor who is not signed in" do
    assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(build_conn(), ~p"/depot/holdings")
  end
end
