defmodule AbakusWeb.AreasTest do
  use AbakusWeb.ConnCase

  import Phoenix.LiveViewTest
  import Abakus.DomainFixtures
  import Abakus.KasseFixtures
  import Abakus.UsersFixtures

  alias Abakus.Kasse.Participants

  # With a real id in every route param, so the area alone answers 404.
  defp get_paths(prefix, id) do
    paths =
      for %{verb: :get, path: path} <- AbakusWeb.Router.__routes__(),
          String.starts_with?(path, prefix),
          do: String.replace(path, ~r"[:*]\w+", Integer.to_string(id))

    assert prefix in paths
    paths
  end

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
      account = account_fixture(name: "Girokonto")
      user = user_fixture()

      %{conn: log_in_user(conn, user), user: user, account: account}
    end

    test "gets 404 on every Budget page", %{conn: conn, account: account} do
      for path <- get_paths("/budget", account.id) do
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

  describe "a person of the Kasse who does not own the budget" do
    setup %{conn: conn} do
      _owner = user_fixture()
      account = account_fixture(name: "Girokonto")
      dora = person!("Dora")

      %{conn: log_in_participant(conn, dora.id), account: account}
    end

    test "sees only the Kasse, under its name and without a switcher", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/kasse")

      assert has_element?(view, "header .navbar", "Kasse")
      refute has_element?(view, "#area-switcher")
      refute has_element?(view, "aside nav .menu-title")
      refute has_element?(view, ~s|a[href^="/budget"]|)
      refute html =~ "Girokonto"
      assert has_element?(view, sidebar_link("/kasse") <> "[aria-current=page]", "Ausgaben")
      assert has_element?(view, ".dock a[href='/kasse/balances']", "Salden")
    end

    test "opens the Kasse from / and gets 404 on every Budget page", %{
      conn: conn,
      account: account
    } do
      assert conn |> get(~p"/") |> redirected_to() == ~p"/kasse"

      for path <- get_paths("/budget", account.id) do
        assert_error_sent 404, fn -> get(conn, path) end
      end
    end
  end

  describe "a user who is no person of the Kasse" do
    setup :register_and_log_in_user

    setup do
      %{h: household()}
    end

    test "gets 404 on every Kasse page and sees no Kasse in the sidebar", %{conn: conn, h: h} do
      expense = create!(equal(h, "Essen", 3000, "2026-10-01", h.anna, [h.anna, h.ben]))

      for path <- get_paths("/kasse", expense.id) do
        assert_error_sent 404, fn -> get(conn, path) end
      end

      {:ok, view, _html} = live(conn, ~p"/budget")
      refute has_element?(view, ~s|a[href^="/kasse"]|)
      refute has_element?(view, "#area-switcher")
    end

    test "an archived person among them", %{h: h} do
      anna = Participants.get_participant!(h.anna)
      {:ok, _anna} = Participants.archive_participant(nil, anna)
      conn = log_in_participant(build_conn(), anna.id)

      assert_error_sent 404, fn -> get(conn, ~p"/kasse") end
    end
  end

  describe "the budget owner who is a person of the Kasse" do
    setup :register_and_log_in_user

    setup %{user: user} do
      {:ok, olga} =
        Participants.create_participant(nil, %{name: "Olga", email: user.email})

      %{olga: olga}
    end

    test "switches between Budget and Kasse from the sidebar and the title", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/kasse")

      assert has_element?(view, "aside nav .menu-title", "Budget")
      assert has_element?(view, "aside nav .menu-title", "Kasse")
      assert has_element?(view, sidebar_link("/budget"))
      assert has_element?(view, sidebar_link("/kasse") <> "[aria-current=page]")
      assert has_element?(view, ~s|#area-switcher a[href="/budget"]|)
      assert has_element?(view, ~s|#area-switcher a[href="/kasse"][aria-current=page]|)

      assert get_session(get(conn, ~p"/kasse/export/expenses.csv"), :area) == "kasse"
    end

    test "sees the account groups as Budgetkonten and Trackingkonten", %{conn: conn} do
      account_fixture(name: "Girokonto")
      account_fixture(name: "Depot", kind: :tracking)

      {:ok, view, _html} = live(conn, ~p"/kasse")

      assert has_element?(view, "aside nav .menu-title", "Budgetkonten")
      assert has_element?(view, "aside nav .menu-title", "Trackingkonten")
    end
  end
end
