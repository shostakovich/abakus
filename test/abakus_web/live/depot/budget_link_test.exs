defmodule AbakusWeb.Depot.BudgetLinkTest do
  use AbakusWeb.ConnCase

  import Abakus.DomainFixtures, only: [budget_scope: 0]
  import Phoenix.LiveViewTest
  import Ecto.Query, only: [from: 2]
  import Abakus.Depot.{PortfoliosFixtures, SecuritiesFixtures}

  alias Abakus.Depot.{AccountRoles, BudgetLink, Portfolios}
  alias Abakus.{DomainFixtures, Ledger, Repo}
  alias Setzkasten.Test.Confirm

  setup :register_and_log_in_user

  setup %{scope: scope} do
    giro = DomainFixtures.account_fixture(name: "Giro")
    investieren = DomainFixtures.category_fixture(name: "Investieren")

    {:ok, portfolio} =
      Portfolios.create_portfolio(scope, %{name: "Langfristig", account_name: "Cash"})

    clearing = account_fixture(scope, %{name: "Giro-Verrechnung"})
    {:ok, clearing} = AccountRoles.set_role(scope, clearing, "budget_account:#{giro.id}")
    %{giro: giro, investieren: investieren, portfolio: portfolio, clearing: clearing}
  end

  defp purchase(c) do
    security = security_fixture(%{name: "Welt-ETF"})

    form = %{
      "kind" => "purchase",
      "date" => Date.to_iso8601(Abakus.LocalTime.today()),
      "portfolio_id" => c.portfolio.id,
      "security_id" => security.id,
      "account_id" => c.clearing.id,
      "shares" => "9",
      "price" => "100"
    }

    {:ok, [_]} =
      Portfolios.book_transaction(c.scope, Portfolios.transaction_choices(c.scope), form)

    Repo.one!(
      from t in Ledger.in_register(budget_scope()), where: t.account_id == ^c.giro.id, select: t
    )
  end

  describe "Einstellungen › Depots" do
    test "switches the link on with a start date and the category for purchases", c do
      {:ok, view, _html} = live(c.conn, ~p"/settings/depot/portfolios")
      assert has_element?(view, "#budget-link-state", "Noch nicht mit dem Budget verknüpft")

      view
      |> form("#budget-link-form",
        link: %{start_date: "2026-10-01", category_id: c.investieren.id}
      )
      |> render_change()

      Confirm.confirm_click(view, "#budget-link-submit", "Mit Budget verknüpfen?")

      assert has_element?(view, "#flash-info", "Mit dem Budget verknüpft.")
      assert has_element?(view, "#budget-link-state", "Seit dem 01.10.2026")
      refute has_element?(view, "#budget-link-form")

      assert %{start_date: ~D[2026-10-01], category_id: category_id} = BudgetLink.get(c.scope)
      assert category_id == c.investieren.id
    end

    test "changes the category of later purchases", c do
      {:ok, _} =
        BudgetLink.switch_on(c.scope, %{category_id: c.investieren.id, start_date: ~D[2026-10-01]})

      other = DomainFixtures.category_fixture(name: "Sparen")

      {:ok, view, _html} = live(c.conn, ~p"/settings/depot/portfolios")

      view
      |> form("#budget-category-form", link: %{category_id: other.id})
      |> render_submit()

      assert has_element?(view, "#flash-info", "Kategorie für Käufe gespeichert.")
      assert BudgetLink.get(c.scope).category_id == other.id
    end
  end

  test "someone who does not own the budget sees no link" do
    %{conn: conn} = register_and_log_in_user(%{conn: build_conn()})
    {:ok, view, _html} = live(conn, ~p"/settings/depot/portfolios")
    refute has_element?(view, "#budget-link")
  end

  test "the register keeps amount, date and payee of a linked transaction", c do
    {:ok, _} =
      BudgetLink.switch_on(c.scope, %{category_id: c.investieren.id, start_date: ~D[2026-01-01]})

    outflow = purchase(c)

    {:ok, view, _html} = live(c.conn, ~p"/budget/accounts/#{c.giro}")
    view |> element("#tx-#{outflow.id} td.app-payee") |> render_click()
    view |> element("#tx-#{outflow.id} td.app-payee") |> render_click()

    assert has_element?(view, ~s|#tx-depot a[href="/depot/transactions"]|, "Buchung im Depot")

    for field <- ~w(tx-date tx-outflow tx-inflow) do
      assert has_element?(view, "##{field}[disabled]")
    end

    refute has_element?(view, "#tx-delete")
  end
end
