defmodule AbakusWeb.AccountOrderTest do
  use AbakusWeb.ConnCase

  import Phoenix.LiveViewTest
  import Abakus.DomainFixtures

  alias Abakus.Depot.PortfoliosFixtures
  alias Abakus.{Ledger, UsersFixtures}
  alias Abakus.Users.Scope

  setup :register_and_log_in_user

  setup do
    %{
      giro: account_fixture(name: "Girokonto", kind: :checking),
      spar: account_fixture(name: "Sparkonto", kind: :savings),
      bar: account_fixture(name: "Bargeld", kind: :cash)
    }
  end

  defp sidebar(view, accounts) do
    names = Map.new(accounts, &{"side-account-#{&1.id}-sidebar", &1.name})

    view
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.query("aside [id^='side-account-'][id$='-sidebar']")
    |> LazyHTML.attribute("id")
    |> Enum.filter(&Map.has_key?(names, &1))
    |> Enum.map(&names[&1])
  end

  defp positions(scope), do: Map.new(Ledger.list_accounts(scope), &{&1.id, &1.position})

  defp picker(view) do
    view
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.query("#tx-account option")
    |> Enum.map(&LazyHTML.text/1)
  end

  defp move(view, section, account, index),
    do:
      render_hook(view, "move_account", %{
        "section" => section,
        "id" => account.id,
        "index" => index
      })

  test "a dragged account takes its new place in the sidebar", c do
    accounts = [c.giro, c.spar, c.bar]
    {:ok, view, _html} = live(c.conn, ~p"/budget")

    move(view, "Budgetkonten", c.bar, 0)
    assert sidebar(view, accounts) == ["Bargeld", "Girokonto", "Sparkonto"]

    move(view, "Budgetkonten", c.bar, 2)
    assert sidebar(view, accounts) == ["Girokonto", "Sparkonto", "Bargeld"]
  end

  test "an account dragged into the other section stays in its own", c do
    haus = account_fixture(name: "Haus", kind: :tracking)
    accounts = [c.giro, c.spar, c.bar, haus]
    {:ok, view, _html} = live(c.conn, ~p"/budget/accounts/all")

    move(view, "Trackingkonten", c.giro, 0)

    assert sidebar(view, accounts) == ["Girokonto", "Sparkonto", "Bargeld", "Haus"]
    assert has_element?(view, "#side-account-#{c.giro.id}-sidebar")
  end

  test "a portfolio's cash, which the sidebar leaves out, does not shift the place", c do
    haus = account_fixture(name: "Haus", kind: :tracking)
    cash = account_fixture(name: "Verrechnungskonto", kind: :tracking)
    auto = account_fixture(name: "Auto", kind: :tracking)
    boot = account_fixture(name: "Boot", kind: :tracking)
    PortfoliosFixtures.portfolio_fixture(budget_scope(), %{reference_account_id: cash.id})
    {:ok, view, _html} = live(c.conn, ~p"/depot")

    move(view, "Trackingkonten", boot, 1)

    assert sidebar(view, [haus, auto, boot]) == ["Haus", "Boot", "Auto"]
  end

  test "the register's account picker follows a move", c do
    {:ok, view, _html} = live(c.conn, ~p"/budget/accounts/all")
    view |> element("#new-transaction") |> render_click()

    move(view, "Budgetkonten", c.bar, 0)

    assert picker(view) == ["Bargeld", "Girokonto", "Sparkonto"]
  end

  test "a refused move shows the order another device set meanwhile", c do
    accounts = [c.giro, c.spar, c.bar]
    {:ok, view, _html} = live(c.conn, ~p"/budget")
    {:ok, _group} = Ledger.move_account(budget_scope(), c.bar.id, c.giro.id)

    move(view, "Trackingkonten", c.giro, 0)

    assert sidebar(view, accounts) == ["Bargeld", "Girokonto", "Sparkonto"]
  end

  test "a move with malformed params changes nothing", c do
    {:ok, view, _html} = live(c.conn, ~p"/budget")
    before = positions(budget_scope())

    move(view, "Budgetkonten", c.bar, "0")
    move(view, "Budgetkonten", c.bar, -1)
    render_hook(view, "move_account", %{"section" => "Budgetkonten", "id" => c.bar.id})
    render_hook(view, "move_account", %{})

    assert positions(budget_scope()) == before
  end

  test "another user's account is not moved", c do
    other = Scope.for_user(UsersFixtures.user_fixture())
    foreign = PortfoliosFixtures.account_fixture(other, name: "Fremd", kind: :checking)
    PortfoliosFixtures.account_fixture(other, name: "Auch fremd", kind: :checking)
    {:ok, view, _html} = live(c.conn, ~p"/budget")
    before = {positions(budget_scope()), positions(other)}

    move(view, "Budgetkonten", foreign, 0)

    assert {positions(budget_scope()), positions(other)} == before
  end

  test "a user without the Budget moves nothing" do
    user = UsersFixtures.user_fixture()
    scope = Scope.for_user(user)
    PortfoliosFixtures.portfolio_fixture(scope)
    first = PortfoliosFixtures.account_fixture(scope, name: "Erstes", kind: :checking)
    last = PortfoliosFixtures.account_fixture(scope, name: "Letztes", kind: :checking)
    {:ok, view, _html} = live(log_in_user(build_conn(), user), ~p"/depot")
    before = positions(scope)

    move(view, "Budgetkonten", last, 0)

    assert positions(scope) == before
    assert Map.fetch!(before, first.id) < Map.fetch!(before, last.id)
  end
end
