defmodule AbakusWeb.Depot.PortfoliosLiveTest do
  use AbakusWeb.ConnCase

  import Phoenix.LiveViewTest
  import Abakus.Depot.PortfoliosFixtures

  alias Abakus.Depot.Portfolios
  alias Abakus.Depot.Portfolios.Portfolio
  alias Abakus.Repo
  alias AbakusWeb.Depot.Components

  setup :register_and_log_in_user

  test "is the Depot's section of the settings", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/settings/depot/portfolios")

    assert has_element?(
             lv,
             ~s|#settings-depots-sidebar[href="/settings/depot/portfolios"][aria-current=page]|,
             "Depots"
           )

    assert has_element?(lv, "h1", "Depots")
  end

  test "shows a portfolio without a name as „Ohne Namen“", ctx do
    portfolio = portfolio_fixture(ctx.scope, %{name: ""})
    path = Components.depots_path(:holdings, portfolio.id)

    {:ok, lv, _html} = live(ctx.conn, ~p"/settings/depot/portfolios")
    assert has_element?(lv, "#portfolio-row-#{portfolio.id}", "Ohne Namen")

    {:ok, lv, _html} = live(ctx.conn, ~p"/depot")
    assert has_element?(lv, sidebar_link(path), "Ohne Namen")
    assert has_element?(lv, ~s(#portfolio-#{portfolio.id} a[href="#{path}"]), "Ohne Namen")

    {:ok, lv, _html} = live(ctx.conn, path)
    assert has_element?(lv, "#portfolio-menu summary", "Ohne Namen")
    assert has_element?(lv, "#portfolio-menu a", "Ohne Namen")
  end

  describe "a new portfolio" do
    test "comes with its Verrechnungskonto, a tracking account that is its cash", %{
      conn: conn,
      scope: scope
    } do
      {:ok, lv, _html} = live(conn, ~p"/settings/depot/portfolios")
      refute has_element?(lv, "#depot-numbers")

      lv
      |> form("#new-portfolio-form",
        portfolio: %{name: " Langfristig ", account_name: "Girokonto"}
      )
      |> render_submit()

      assert render(lv) =~ "Depot „Langfristig“ angelegt."
      assert [%{name: "Langfristig"} = portfolio] = Portfolios.list_portfolios(scope)
      assert [%{name: "Girokonto", kind: :tracking} = account] = Portfolios.list_accounts(scope)
      assert portfolio.reference_account_id == account.id
      assert Portfolios.cash_account_portfolios(scope) == %{account.id => portfolio.id}

      assert has_element?(
               lv,
               "#portfolio-row-#{portfolio.id}",
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

  describe "editing a portfolio" do
    test "shows each active portfolio's depot number masked with its accounts", ctx do
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
               "#portfolio-row-#{portfolio.id}",
               "Depotnummer …4472\u2060\u00A0· Verrechnungskonto „Konto Sparplan“"
             )

      refute render(lv) =~ "123 456 4472"
      assert has_element?(lv, "#portfolio-row-#{other.id}", "Keine Depotnummer")
      refute has_element?(lv, "#portfolio-row-#{other.id}", "Verrechnungskonto")
      refute has_element?(lv, "#portfolios #portfolio-row-#{retired.id}")
      assert has_element?(lv, "#retired-portfolios #portfolio-row-#{retired.id}", "Alt")
    end

    test "edits a retired portfolio in the same dialog", ctx do
      account = account_fixture(ctx.scope, %{name: "Alt-Cash", closed: true})
      giro = account_fixture(ctx.scope, %{name: "Giro", kind: :checking})

      retired =
        portfolio_fixture(ctx.scope, %{
          name: "Alt",
          retired: true,
          reference_account_id: account.id
        })

      {:ok, lv, _html} = live(ctx.conn, ~p"/settings/depot/portfolios")
      lv |> element("#portfolio-#{retired.id}-edit") |> render_click()

      assert has_element?(lv, "#portfolio-form_reference_account_id option[selected]", "Alt-Cash")

      lv
      |> form("#portfolio-form", portfolio: %{reference_account_id: giro.id})
      |> render_submit()

      assert has_element?(lv, "#retired-portfolios #portfolio-row-#{retired.id}", "„Giro“")
    end

    test "edits the depot number and refuses the digits of another portfolio", ctx do
      portfolio_fixture(ctx.scope, %{name: "Sparplan", depot_number: "4472"})
      account = account_fixture(ctx.scope, %{name: "Broker"})

      portfolio =
        portfolio_fixture(ctx.scope, %{name: "Langfristig", reference_account_id: account.id})

      {:ok, lv, _html} = live(ctx.conn, ~p"/settings/depot/portfolios")
      lv |> element("#portfolio-#{portfolio.id}-edit") |> render_click()

      assert has_element?(lv, "#portfolio-dialog h2", "Langfristig")

      assert lv
             |> form("#portfolio-form", portfolio: %{depot_number: "44-72"})
             |> render_change() =~ "Gehört schon zu „Sparplan“"

      lv
      |> form("#portfolio-form", portfolio: %{depot_number: "DE 0815 4471"})
      |> render_submit()

      assert render(lv) =~ "Depot „Langfristig“ gespeichert."
      refute has_element?(lv, "#portfolio-form")
      assert has_element?(lv, "#portfolio-row-#{portfolio.id}", "Depotnummer …4471")
      assert Repo.get!(Portfolio, portfolio.id).depot_number == "DE 0815 4471"

      lv |> element("#portfolio-#{portfolio.id}-edit") |> render_click()
      assert has_element?(lv, "#portfolio-form input[value='DE 0815 4471']")
      lv |> form("#portfolio-form", portfolio: %{depot_number: ""}) |> render_submit()

      assert has_element?(lv, "#portfolio-row-#{portfolio.id}", "Keine Depotnummer")
    end

    test "changes the Verrechnungskonto, offering no other portfolio's cash", ctx do
      broker = account_fixture(ctx.scope, %{name: "Broker"})
      giro = account_fixture(ctx.scope, %{name: "Giro", kind: :checking})
      taken = account_fixture(ctx.scope, %{name: "Vergeben"})

      portfolio =
        portfolio_fixture(ctx.scope, %{name: "Langfristig", reference_account_id: broker.id})

      portfolio_fixture(ctx.scope, %{name: "Anderes", reference_account_id: taken.id})

      {:ok, lv, _html} = live(ctx.conn, ~p"/settings/depot/portfolios")
      lv |> element("#portfolio-#{portfolio.id}-edit") |> render_click()

      assert has_element?(lv, "#portfolio-form_reference_account_id option[selected]", "Broker")
      assert has_element?(lv, "#portfolio-form_reference_account_id option", "Giro")
      refute has_element?(lv, "#portfolio-form_reference_account_id option", "Vergeben")
      refute has_element?(lv, "#portfolio-form_cash_account_ids")

      lv
      |> form("#portfolio-form", portfolio: %{reference_account_id: giro.id})
      |> render_submit()

      assert has_element?(lv, "#portfolio-row-#{portfolio.id}", "Verrechnungskonto „Giro“")
      assert Repo.get!(Portfolio, portfolio.id).reference_account_id == giro.id
    end

    test "refuses a tracking account another portfolio took after the dialog opened", ctx do
      broker = account_fixture(ctx.scope, %{name: "Broker"})
      free = account_fixture(ctx.scope, %{name: "Frei"})

      portfolio =
        portfolio_fixture(ctx.scope, %{name: "Langfristig", reference_account_id: broker.id})

      {:ok, lv, _html} = live(ctx.conn, ~p"/settings/depot/portfolios")
      lv |> element("#portfolio-#{portfolio.id}-edit") |> render_click()
      portfolio_fixture(ctx.scope, %{name: "Anderes", reference_account_id: free.id})

      lv
      |> form("#portfolio-form", portfolio: %{reference_account_id: free.id})
      |> render_submit()

      assert has_element?(lv, "#portfolio-form", "Ist schon das Verrechnungskonto von „Anderes“")
      assert Repo.get!(Portfolio, portfolio.id).reference_account_id == broker.id
    end

    test "cancels editing", ctx do
      portfolio = portfolio_fixture(ctx.scope, %{name: "Sparplan"})

      {:ok, lv, _html} = live(ctx.conn, ~p"/settings/depot/portfolios")
      lv |> element("#portfolio-#{portfolio.id}-edit") |> render_click()
      lv |> element("#portfolio-form button", "Abbrechen") |> render_click()

      refute has_element?(lv, "#portfolio-form")
    end
  end

  describe "a portfolio's cash" do
    setup %{scope: scope} do
      cash = account_fixture(scope, %{name: "Scalable"})
      giro = account_fixture(scope, %{name: "Giro", kind: :checking})

      broker =
        portfolio_fixture(scope, %{name: "Scalable Capital", reference_account_id: cash.id})

      bank = portfolio_fixture(scope, %{name: "Comdirect Depot", reference_account_id: giro.id})
      %{cash: cash, broker: broker, bank: bank}
    end

    test "is renamed, closed and reopened in the account dialog", ctx do
      {:ok, lv, _html} = live(ctx.conn, ~p"/settings/depot/portfolios")

      refute has_element?(lv, "#portfolio-#{ctx.bank.id}-account")
      lv |> element("#portfolio-#{ctx.broker.id}-account") |> render_click()

      assert has_element?(lv, "#account-dialog h2", "Konto bearbeiten")
      refute has_element?(lv, "#account-form_kind")

      lv
      |> form("#account-form", account: %{name: "Scalable Cash", note: "Beim Broker"})
      |> render_submit()

      assert has_element?(lv, "#flash-info", "Konto gespeichert")
      refute has_element?(lv, "#account-dialog")

      assert has_element?(
               lv,
               "#portfolio-row-#{ctx.broker.id}",
               "Verrechnungskonto „Scalable Cash“"
             )

      assert %{name: "Scalable Cash", note: "Beim Broker"} =
               Abakus.Ledger.get_account!(ctx.scope, ctx.cash.id)

      lv |> element("#portfolio-#{ctx.broker.id}-account") |> render_click()
      confirm_click(lv, "#close-account")

      assert Abakus.Ledger.get_account!(ctx.scope, ctx.cash.id).closed
      assert has_element?(lv, "#flash-info", "Konto geschlossen")

      lv |> element("#portfolio-#{ctx.broker.id}-account") |> render_click()
      assert has_element?(lv, "#account-closed")
      lv |> element("#reopen-account") |> render_click()

      refute Abakus.Ledger.get_account!(ctx.scope, ctx.cash.id).closed
    end

    test "opens no account dialog for a budget account or an unknown portfolio", ctx do
      {:ok, lv, _html} = live(ctx.conn, ~p"/settings/depot/portfolios")

      for id <- [ctx.bank.id, -1] do
        render_hook(lv, "edit_account", %{id: id})
        refute has_element?(lv, "#account-dialog")
      end
    end

    test "closes the account dialog on cancel", ctx do
      {:ok, lv, _html} = live(ctx.conn, ~p"/settings/depot/portfolios")
      lv |> element("#portfolio-#{ctx.broker.id}-account") |> render_click()
      lv |> element("#account-cancel") |> render_click()

      refute has_element?(lv, "#account-dialog")
    end
  end
end
