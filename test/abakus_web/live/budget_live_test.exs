defmodule AbakusWeb.BudgetLiveTest do
  use AbakusWeb.ConnCase

  import Phoenix.LiveViewTest

  test "anonymous visitors are sent to the sign-in page", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/")
  end

  describe "signed in" do
    setup :register_and_log_in_user

    test "the start page shows the budget placeholder and the navigation", %{
      conn: conn,
      user: user
    } do
      {:ok, view, html} = live(conn, ~p"/")

      assert html =~ "<h1"
      assert has_element?(view, "h1", "Budget")
      assert has_element?(view, "#theme-switch[phx-hook=ThemeSwitch]")

      for label <- ["Hell", "Dunkel", "Auto"] do
        assert has_element?(view, "#theme-switch label", label)
      end

      assert has_element?(view, ~s|nav a.active[aria-current=page][href="/"]|, "Budget")
      assert has_element?(view, ~s|nav a[href="/users/settings"]|, "Einstellungen")

      assert has_element?(
               view,
               ~s|#log-out[href="/users/log-out"][data-method=delete][title="#{user.email}"]|,
               "Abmelden"
             )
    end
  end
end
