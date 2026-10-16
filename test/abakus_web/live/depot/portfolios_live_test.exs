defmodule AbakusWeb.Depot.PortfoliosLiveTest do
  use AbakusWeb.ConnCase

  import Phoenix.LiveViewTest
  import Abakus.Depot.PortfoliosFixtures

  alias Abakus.Depot.Portfolios
  alias Abakus.Depot.Portfolios.Portfolio
  alias Abakus.Repo
  alias AbakusWeb.Depot.Components

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
    path = Components.depots_path(:holdings, portfolio.id)

    {:ok, lv, _html} = live(ctx.conn, ~p"/settings/depot/portfolios")
    assert has_element?(lv, "#depot-number-#{portfolio.id}", "Ohne Namen")

    {:ok, lv, _html} = live(ctx.conn, ~p"/depot")
    assert has_element?(lv, sidebar_link(path), "Ohne Namen")
    assert has_element?(lv, ~s(#portfolio-#{portfolio.id} a[href="#{path}"]), "Ohne Namen")

    {:ok, lv, _html} = live(ctx.conn, path)
    assert has_element?(lv, "#portfolio-menu summary", "Ohne Namen")
    assert has_element?(lv, "#portfolio-menu a", "Ohne Namen")
  end

  describe "the roles of the Verrechnungskonten" do
    setup %{scope: scope} do
      giro = Abakus.DomainFixtures.account_fixture(name: "Giro", kind: :checking)
      portfolio = portfolio_fixture(scope, %{name: "Broker"})
      account = account_fixture(scope, %{name: "Giro-Verrechnung"})
      %{giro: giro, portfolio: portfolio, account: account}
    end

    test "sets a role in place", ctx do
      {:ok, lv, _html} = live(ctx.conn, ~p"/settings/depot/portfolios")
      row = "#clearing-account-#{ctx.account.id}"
      assert has_element?(lv, row, "Rolle fehlt")

      lv |> element("#{row} button", "Festlegen") |> render_click()

      assert has_element?(
               lv,
               ~s|#account-role-form option[value="budget_account:#{ctx.giro.id}"]|
             )

      lv
      |> form("#account-role-form", role: %{role: "budget_account:#{ctx.giro.id}"})
      |> render_submit()

      assert render(lv) =~ "Rolle von „Giro-Verrechnung“ gespeichert."
      assert has_element?(lv, row, "ist Budgetkonto „Giro“")
      refute has_element?(lv, row, "Rolle fehlt")

      lv |> element("#{row} button", "Ändern") |> render_click()

      lv
      |> form("#account-role-form", role: %{role: "portfolio_cash:#{ctx.portfolio.id}"})
      |> render_submit()

      assert has_element?(lv, row, "Cash von Depot „Broker“")
    end

    test "offers a Verrechnungskonto in another currency no budget account", ctx do
      usd = account_fixture(ctx.scope, %{name: "USD-Cash", currency: "USD"})
      {:ok, lv, _html} = live(ctx.conn, ~p"/settings/depot/portfolios")

      lv |> element("#clearing-account-#{usd.id} button", "Festlegen") |> render_click()

      refute has_element?(lv, ~s|#account-role-form option[value^="budget_account:"]|)

      assert has_element?(
               lv,
               ~s|#account-role-form option[value="portfolio_cash:#{ctx.portfolio.id}"]|
             )

      assert has_element?(lv, ~s|#account-role-form option[value="none"]|)
    end

    test "shows why a role was refused", ctx do
      {:ok, lv, _html} = live(ctx.conn, ~p"/settings/depot/portfolios")
      lv |> element("#clearing-account-#{ctx.account.id} button", "Festlegen") |> render_click()
      Repo.update!(Ecto.Changeset.change(ctx.giro, closed: true))

      lv
      |> form("#account-role-form", role: %{role: "budget_account:#{ctx.giro.id}"})
      |> render_submit()

      assert has_element?(lv, "#account-role-form", "Das ist kein offenes Budgetkonto.")
    end
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
end
