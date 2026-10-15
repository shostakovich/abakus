defmodule AbakusWeb.AreasTest do
  use AbakusWeb.ConnCase

  import Phoenix.LiveViewTest
  import Abakus.DomainFixtures
  import Abakus.UsersFixtures

  describe "the budget owner" do
    setup :register_and_log_in_user

    test "opens the Budget from /", %{conn: conn} do
      assert conn |> get(~p"/") |> redirected_to() == ~p"/budget"
    end

    test "opens the area used last, kept in the session", %{conn: conn} do
      conn = get(conn, ~p"/budget/accounts")
      assert get_session(conn, :area) == "budget"

      assert conn |> recycle() |> get(~p"/") |> redirected_to() == ~p"/budget"
    end

    test "falls back to an area they may use when the one used last is gone", %{conn: conn} do
      conn = Plug.Test.init_test_session(conn, area: "depot")

      assert conn |> get(~p"/") |> redirected_to() == ~p"/budget"
    end

    test "with the Budget as their only area: the brand is its name and there is no switcher", %{
      conn: conn
    } do
      {:ok, view, _html} = live(conn, ~p"/budget")

      assert has_element?(view, "header .navbar", "Budget")
      refute has_element?(view, "header .navbar", "Abakus")
      refute has_element?(view, "#area-switcher")
      refute has_element?(view, "aside nav .menu-title", "Budget")
    end
  end

  describe "a user who does not own the budget" do
    setup %{conn: conn} do
      _owner = user_fixture()
      account_fixture(name: "Girokonto")
      user = user_fixture()

      %{conn: log_in_user(conn, user), user: user}
    end

    test "gets 404 on every Budget page", %{conn: conn} do
      budget_routes =
        for %{verb: :get, path: "/budget" <> _ = path} <- AbakusWeb.Router.__routes__(),
            do: String.replace(path, ~r"[:*]\w+", "1")

      assert ~p"/budget" in budget_routes

      for path <- budget_routes do
        assert_error_sent 404, fn -> get(conn, path) end
      end

      assert_error_sent 404, fn -> get(conn, ~p"/settings/ynab") end
    end

    test "sees no Budget in the sidebar or the settings", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/settings")

      refute has_element?(view, ~s|a[href^="/budget"]|)
      refute has_element?(view, "#side-add-account-sidebar")
      refute html =~ "Girokonto"
      refute has_element?(view, ~s|#settings-nav a[href="/settings/ynab"]|)
      assert has_element?(view, ~s|#settings-nav a[href="/settings/access"]|)
    end

    test "is sent to the settings by /, never to the Budget used before", %{conn: conn} do
      conn = Plug.Test.init_test_session(conn, area: "budget")

      assert conn |> get(~p"/") |> redirected_to() == ~p"/settings"
    end
  end
end
