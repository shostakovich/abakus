defmodule AbakusWeb.Depot.SidebarTest do
  use AbakusWeb.ConnCase

  import Abakus.DomainFixtures, only: [budget_scope: 0]
  import Phoenix.LiveViewTest
  import Abakus.Depot.{PortfoliosFixtures, SecuritiesFixtures}

  alias Abakus.Depot.{BudgetFeed, MarketData}
  alias Abakus.{DomainFixtures, Ledger, LocalTime, Repo}
  alias Abakus.Users.{Scope, User}

  setup :register_and_log_in_user_without_budget

  defp today, do: LocalTime.today()

  defp holding(scope, portfolio, count, close) do
    security = security_fixture(quote_feed: :manual)
    price_fixture(security, Date.add(today(), -1), price(close), :pp)

    transaction_fixture(scope, Date.add(today(), -1),
      type: :inbound_delivery,
      portfolio_id: portfolio.id,
      security_id: security.id,
      shares: shares(count)
    )

    security
  end

  defp deposit(scope, account, amount) do
    transaction_fixture(scope, Date.add(today(), -1),
      type: :deposit,
      account_id: account.id,
      amount: money(amount)
    )
  end

  test "lists the views, the active portfolios, then the settings, but no accounts", ctx do
    retired = portfolio_fixture(ctx.scope, %{name: "Alt", retired: true})
    holding(ctx.scope, retired, 5, 100)
    closed = account_fixture(ctx.scope, %{name: "Geschlossen", retired: true})
    deposit(ctx.scope, closed, 50)
    portfolio_fixture(ctx.scope, %{name: "Aktiv"})
    account_fixture(ctx.scope, %{name: "Tagesgeld"})

    {:ok, lv, _html} = live(ctx.conn, ~p"/depot/holdings")

    labels =
      lv
      |> render()
      |> LazyHTML.from_document()
      |> LazyHTML.query(~s(aside nav[aria-label="Hauptnavigation"] li))
      |> Enum.map(&(&1 |> LazyHTML.text() |> String.split() |> hd()))

    assert Enum.drop_while(labels, &(&1 != "Vermögen")) ==
             ~w(Vermögen Alle Import Depots Aktiv Einstellungen)

    assert has_element?(lv, "#holdings-portfolio-#{retired.id}")
    refute has_element?(lv, sidebar_link(~p"/depot/holdings?#{[portfolio: retired.id]}"))
  end

  test "marks „Depots“ for a retired portfolio, which it leaves out", ctx do
    retired = portfolio_fixture(ctx.scope, %{name: "Alt", retired: true})
    holding(ctx.scope, retired, 5, 100)

    {:ok, lv, _html} = live(ctx.conn, ~p"/depot/holdings?#{[portfolio: retired.id]}")
    assert has_element?(lv, sidebar_link("/depot/holdings") <> "[aria-current=page]")
  end

  test "leaves „Buchung erfassen“ to the Depots pages", ctx do
    portfolio_fixture(ctx.scope)
    {:ok, lv, _html} = live(ctx.conn, ~p"/depot")

    refute has_element?(lv, "#app-shell", "Buchung erfassen")
    refute has_element?(lv, "#fab-book")

    {:ok, lv, _html} = live(ctx.conn, ~p"/depot/holdings")
    lv |> element("#depots-book") |> render_click()
    assert has_element?(lv, "#transaction-modal h2", "Buchung erfassen")
  end

  describe "the portfolios" do
    setup %{scope: scope} do
      account = account_fixture(scope, %{name: "Konto Langfristig"})
      deposit(scope, account, 240)
      portfolio = portfolio_fixture(scope, %{reference_account_id: account.id})
      holding(scope, portfolio, 10, 100)
      savings = account_fixture(scope, %{name: "Tagesgeld"})
      deposit(scope, savings, 1_000)

      %{
        account: account,
        portfolio: portfolio,
        portfolio_path: ~p"/depot/holdings?#{[portfolio: portfolio.id]}"
      }
    end

    test "show each portfolio's securities, while net worth holds the accounts too", ctx do
      {:ok, lv, _html} = live(ctx.conn, ~p"/depot")

      assert lv |> element(sidebar_link(ctx.portfolio_path)) |> render() =~ "1.000,00"
      refute has_element?(lv, "aside nav", "Tagesgeld")
      assert lv |> element("#net-worth") |> render() =~ "2.240 €"
    end

    test "stay out of the icon rail, which keeps the views and the settings", ctx do
      {:ok, lv, _html} = live(ctx.conn, ~p"/depot")

      rail = "#app-shell-rail"
      refute has_element?(lv, "#{rail} a[href='#{ctx.portfolio_path}']")
      assert has_element?(lv, "#{rail} a[href='/depot/holdings']")
      assert has_element?(lv, "#{rail} a[href='/settings']")
      assert has_element?(lv, sidebar_link(ctx.portfolio_path))
    end

    test "mark the open portfolio, or the screen", ctx do
      {:ok, lv, _html} = live(ctx.conn, ctx.portfolio_path)

      assert has_element?(lv, sidebar_link(ctx.portfolio_path) <> "[aria-current=page]")
      refute has_element?(lv, sidebar_link("/depot/holdings") <> "[aria-current]")

      {:ok, lv, _html} = live(ctx.conn, ~p"/depot/holdings")

      assert has_element?(lv, sidebar_link("/depot/holdings") <> "[aria-current=page]")
      refute has_element?(lv, sidebar_link(ctx.portfolio_path) <> "[aria-current]")

      {:ok, lv, _html} = live(ctx.conn, ~p"/depot")

      assert has_element?(lv, sidebar_link("/depot") <> "[aria-current=page]")
    end

    test "update when new prices arrive, also on a page without prices", ctx do
      {:ok, lv, _html} = live(ctx.conn, ~p"/depot/transactions")

      Repo.update_all(Abakus.Depot.Securities.Security,
        set: [latest_date: today(), latest_close: price(110)]
      )

      MarketData.run_daily()

      assert lv |> element(sidebar_link(ctx.portfolio_path)) |> render() =~ "1.100,00"
    end
  end

  test "shows only the user's own portfolios", ctx do
    portfolio_fixture(ctx.scope, %{name: "Eigenes Depot"})
    other = Abakus.UsersFixtures.user_scope_fixture()
    deposit(other, account_fixture(other, %{name: "Fremdes Konto"}), 1)
    holding(other, portfolio_fixture(other, %{name: "Fremdes Depot"}), 1, 100)

    {:ok, lv, _html} = live(ctx.conn, ~p"/depot")

    sidebar = ~s(aside nav[aria-label="Hauptnavigation"])
    assert has_element?(lv, sidebar, "Eigenes Depot")
    refute has_element?(lv, sidebar, "Fremd")
    refute has_element?(lv, sidebar, "Verrechnungskonten")
  end

  test "shows no count on the tab „Buchungen“ while the inbox is empty", ctx do
    portfolio_fixture(ctx.scope)
    {:ok, lv, _html} = live(ctx.conn, ~p"/depot/holdings")

    assert has_element?(lv, ~s(#depots-tabs a[href="/depot/transactions"]), "Buchungen")
    refute has_element?(lv, "#inbox-count")
  end

  describe "on the budget's pages" do
    setup do
      owner = Repo.get_by!(User, budget_owner: true)
      %{owner: Scope.for_user(owner), conn: log_in_user(build_conn(), owner)}
    end

    test "lists the portfolios too, kept up to date with the prices", ctx do
      portfolio = portfolio_fixture(ctx.owner, %{name: "Langfristig"})
      holding(ctx.owner, portfolio, 10, 100)
      path = ~p"/depot/holdings?#{[portfolio: portfolio.id]}"

      giro = DomainFixtures.account_fixture(name: "Girokonto")
      {:ok, lv, _html} = live(ctx.conn, ~p"/budget/accounts/#{giro}")

      assert lv |> element(sidebar_link(path)) |> render() =~ "1.000,00"
      assert has_element?(lv, sidebar_link("/depot/holdings"), "Depots")

      Repo.update_all(Abakus.Depot.Securities.Security,
        set: [latest_date: today(), latest_close: price(110)]
      )

      MarketData.run_daily()
      send(lv.pid, :receipts_updated)

      assert lv |> element(sidebar_link(path)) |> render() =~ "1.100,00"
    end

    test "shows a portfolio with the emoji of its account, under the section Depots", ctx do
      portfolio = portfolio_fixture(ctx.owner, %{name: "Langfristig"})
      :ok = BudgetFeed.sync_accounts()
      account = Ledger.get_account!(budget_scope(), Repo.reload!(portfolio).budget_account_id)
      {:ok, _account} = Ledger.update_account(budget_scope(), account, %{name: "📈 Langfristig"})

      {:ok, lv, _html} = live(ctx.conn, ~p"/budget")
      row = lv |> element("#side-depot-portfolio-#{portfolio.id}-sidebar") |> render()

      assert row =~ "📈"
      refute row =~ "📈 Langfristig"
      assert has_element?(lv, "#app-shell-sidebar-full", "Depots")
    end

    test "lists the portfolios right after the accounts and „Konto hinzufügen“",
         ctx do
      portfolio = portfolio_fixture(ctx.owner, %{name: "Langfristig"})
      {:ok, lv, _html} = live(ctx.conn, ~p"/budget/accounts/all")

      ids =
        lv
        |> render()
        |> LazyHTML.from_document()
        |> LazyHTML.query("#app-shell-sidebar-full [id^=side-]")
        |> Enum.flat_map(&LazyHTML.attribute(&1, "id"))
        |> Enum.map(&String.replace_suffix(&1, "-sidebar", ""))

      assert Enum.drop_while(ids, &(not String.starts_with?(&1, "side-depot-portfolio-"))) ==
               ["side-depot-portfolio-#{portfolio.id}", "side-settings"]

      assert Enum.take_while(ids, &(not String.starts_with?(&1, "side-depot-portfolio-")))
             |> List.last() == "side-add-account"
    end

    test "updates the budget accounts' balances after a Depot booking", ctx do
      portfolio_fixture(ctx.owner)
      giro = DomainFixtures.account_fixture(name: "Girokonto")
      {:ok, lv, _html} = live(ctx.conn, ~p"/depot/holdings")

      DomainFixtures.transaction_fixture(account_id: giro.id, amount: 123_400)
      MarketData.broadcast()

      assert lv |> element(sidebar_link(~p"/budget/accounts/#{giro}")) |> render() =~ "1.234,00"
    end
  end
end
