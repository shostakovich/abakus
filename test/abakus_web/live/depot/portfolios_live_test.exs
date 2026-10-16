defmodule AbakusWeb.Depot.PortfoliosLiveTest do
  use AbakusWeb.ConnCase

  import Phoenix.LiveViewTest
  import Abakus.Depot.PortfoliosFixtures

  import Abakus.UsersFixtures, only: [user_fixture: 0]

  alias Abakus.Depot.{BudgetFeed, Portfolios}
  alias Abakus.Depot.Portfolios.Portfolio
  alias Abakus.{DomainFixtures, Ledger, Repo}
  alias Abakus.Users.Scope
  alias AbakusWeb.Depot.Sidebar

  setup :register_and_log_in_user

  test "is the Depot's section of the settings and links the PP import", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/settings/depot/portfolios")

    assert has_element?(
             lv,
             ~s|#settings-depots-sidebar[href="/settings/depot/portfolios"][aria-current=page]|,
             "Depots"
           )

    assert has_element?(lv, "h1", "Depots")
    assert has_element?(lv, ~s|#new-portfolio-import[href="/depot/import"]|)
  end

  test "shows a portfolio without a name, as PP may store one, as „Ohne Namen“", ctx do
    portfolio = portfolio_fixture(ctx.scope, %{name: ""})
    path = Sidebar.portfolio_path(portfolio)

    {:ok, lv, _html} = live(ctx.conn, ~p"/settings/depot/portfolios")
    assert has_element?(lv, "#depot-number-#{portfolio.id}", "Ohne Namen")

    {:ok, lv, _html} = live(ctx.conn, ~p"/depot")
    assert has_element?(lv, sidebar_link(path), "Ohne Namen")
    assert has_element?(lv, ~s(#portfolio-#{portfolio.id} a[href="#{path}"]), "Ohne Namen")

    {:ok, lv, _html} = live(ctx.conn, path)
    assert has_element?(lv, "#portfolio-menu summary", "Ohne Namen")
    assert has_element?(lv, "#portfolio-menu a", "Ohne Namen")
  end

  describe "a new portfolio" do
    test "comes with its Verrechnungskonto", %{conn: conn, scope: scope} do
      {:ok, lv, _html} = live(conn, ~p"/settings/depot/portfolios")
      refute has_element?(lv, "#depot-numbers")

      lv
      |> form("#new-portfolio-form",
        portfolio: %{name: " Langfristig ", account_name: "Girokonto"}
      )
      |> render_submit()

      assert render(lv) =~ "Depot „Langfristig“ angelegt."
      assert [%{name: "Langfristig"} = portfolio] = Portfolios.list_portfolios(scope)
      assert [%{name: "Girokonto", currency: "EUR"} = account] = Portfolios.list_accounts(scope)
      assert portfolio.reference_account_id == account.id

      assert has_element?(
               lv,
               "#depot-number-#{portfolio.id}",
               "Keine Depotnummer\u2060\u00A0· Verrechnungskonto „Girokonto“"
             )
    end

    test "needs a name and an account name", %{conn: conn, scope: scope} do
      {:ok, lv, _html} = live(conn, ~p"/settings/depot/portfolios")

      html =
        lv
        |> form("#new-portfolio-form", portfolio: %{name: " ", account_name: ""})
        |> render_submit()

      assert html =~ "Muss ausgefüllt werden"
      assert Portfolios.list_portfolios(scope) == []
    end
  end

  describe "depot numbers" do
    test "shows each active portfolio's depot number masked with its reference account", ctx do
      account = account_fixture(ctx.scope, %{name: "Konto Sparplan"})

      portfolio =
        portfolio_fixture(ctx.scope, %{
          name: "Sparplan",
          depot_number: "123 456 4472",
          reference_account_id: account.id
        })

      other = portfolio_fixture(ctx.scope, %{name: "Langfristig"})
      retired = portfolio_fixture(ctx.scope, %{name: "Alt", retired: true})

      {:ok, lv, _html} = live(ctx.conn, ~p"/settings/depot/portfolios")

      assert has_element?(
               lv,
               "#depot-number-#{portfolio.id}",
               "Depotnummer …4472\u2060\u00A0· Verrechnungskonto „Konto Sparplan“"
             )

      refute render(lv) =~ "123 456 4472"
      assert has_element?(lv, "#depot-number-#{other.id}", "Keine Depotnummer")
      assert has_element?(lv, "#depot-number-#{other.id} button", "Eintragen")
      refute has_element?(lv, "#depot-number-#{retired.id}")
    end

    test "edits a depot number in place and refuses the digits of another portfolio", ctx do
      portfolio_fixture(ctx.scope, %{name: "Sparplan", depot_number: "4472"})
      portfolio = portfolio_fixture(ctx.scope, %{name: "Langfristig"})

      {:ok, lv, _html} = live(ctx.conn, ~p"/settings/depot/portfolios")
      lv |> element("#depot-number-#{portfolio.id} button", "Eintragen") |> render_click()

      assert lv
             |> form("#depot-number-form", portfolio: %{depot_number: "44-72"})
             |> render_change() =~ "Gehört schon zu „Sparplan“"

      lv
      |> form("#depot-number-form", portfolio: %{depot_number: "DE 0815 4471"})
      |> render_submit()

      assert render(lv) =~ "Depotnummer von „Langfristig“ gespeichert."
      refute has_element?(lv, "#depot-number-form")
      assert has_element?(lv, "#depot-number-#{portfolio.id}", "Depotnummer …4471")
      assert Repo.get!(Portfolio, portfolio.id).depot_number == "DE 0815 4471"

      lv |> element("#depot-number-#{portfolio.id} button", "Ändern") |> render_click()
      assert has_element?(lv, "#depot-number-form input[value='DE 0815 4471']")
      lv |> form("#depot-number-form", portfolio: %{depot_number: ""}) |> render_submit()

      assert has_element?(lv, "#depot-number-#{portfolio.id}", "Keine Depotnummer")
    end

    test "cancels editing", ctx do
      portfolio = portfolio_fixture(ctx.scope, %{name: "Sparplan"})

      {:ok, lv, _html} = live(ctx.conn, ~p"/settings/depot/portfolios")
      lv |> element("#depot-number-#{portfolio.id} button") |> render_click()
      lv |> element("#depot-number-form button", "Abbrechen") |> render_click()

      refute has_element?(lv, "#depot-number-form")
    end
  end

  describe "in the budget" do
    setup ctx do
      portfolio = portfolio_fixture(ctx.scope, %{name: "Langfristig"})
      cash = account_fixture(ctx.scope, %{name: "Verrechnung"})
      depot = DomainFixtures.account_fixture(name: "📈 Depot", kind: :tracking)
      %{portfolio: portfolio, cash: cash, depot: depot}
    end

    test "the budget owner picks the tracking account each portfolio and account feeds", ctx do
      retired = portfolio_fixture(ctx.scope, %{name: "Alt", retired: true})
      DomainFixtures.account_fixture(name: "Giro", kind: :checking)

      {:ok, lv, _html} = live(ctx.conn, ~p"/settings/depot/portfolios")

      assert has_element?(lv, "#budget-feeds", "Wertänderung")

      assert has_element?(
               lv,
               ~s|label[for="feeds_portfolio-#{ctx.portfolio.id}"]|,
               "Depot „Langfristig“"
             )

      assert has_element?(
               lv,
               ~s|label[for="feeds_account-#{ctx.cash.id}"]|,
               "Verrechnungskonto „Verrechnung“"
             )

      refute has_element?(lv, "#feeds_portfolio-#{retired.id}")
      assert has_element?(lv, "#feeds_portfolio-#{ctx.portfolio.id} option", "📈 Depot")
      refute has_element?(lv, "#feeds_portfolio-#{ctx.portfolio.id} option", "Giro")

      lv
      |> form("#budget-feeds-form",
        feeds: %{"portfolio-#{ctx.portfolio.id}" => ctx.depot.id, "account-#{ctx.cash.id}" => ""}
      )
      |> render_submit()

      assert render(lv) =~ "Zuordnung zum Budget gespeichert."
      assert BudgetFeed.feeds(ctx.scope) == %{{:portfolio, ctx.portfolio.id} => ctx.depot.id}
      assert Repo.reload!(ctx.depot).fed_by == :portfolio
      assert has_element?(lv, "#feeds_portfolio-#{ctx.portfolio.id} option[selected]", "📈 Depot")
    end

    test "keeps a feed into an account closed since", ctx do
      {:ok, _feeds} =
        BudgetFeed.put_feeds(ctx.scope, %{{:portfolio, ctx.portfolio.id} => ctx.depot.id})

      {:ok, _closed} = Ledger.update_account(ctx.depot, %{closed: true})
      DomainFixtures.account_fixture(name: "Tagesgeld", kind: :tracking)

      {:ok, lv, _html} = live(ctx.conn, ~p"/settings/depot/portfolios")

      assert has_element?(
               lv,
               "#feeds_portfolio-#{ctx.portfolio.id} option[selected]",
               "📈 Depot (geschlossen)"
             )

      refute has_element?(lv, "#feeds_account-#{ctx.cash.id} option[selected]")

      lv |> form("#budget-feeds-form") |> render_submit()

      assert render(lv) =~ "Zuordnung zum Budget gespeichert."
      assert BudgetFeed.feeds(ctx.scope) == %{{:portfolio, ctx.portfolio.id} => ctx.depot.id}
      assert Repo.reload!(ctx.depot).fed_by == :portfolio
    end

    test "says when the budget has no open tracking account", ctx do
      {:ok, _closed} = Ledger.update_account(ctx.depot, %{closed: true})

      {:ok, lv, _html} = live(ctx.conn, ~p"/settings/depot/portfolios")

      assert has_element?(lv, "#budget-feeds-none", "Tracking-Konto")
      refute has_element?(lv, "#budget-feeds-form")
    end

    test "is not there for anyone else" do
      member = user_fixture()
      portfolio_fixture(Scope.for_user(member))

      {:ok, lv, _html} = live(log_in_user(build_conn(), member), ~p"/settings/depot/portfolios")

      assert has_element?(lv, "#depot-numbers")
      refute has_element?(lv, "#budget-feeds")
    end
  end
end
