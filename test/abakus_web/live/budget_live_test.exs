defmodule AbakusWeb.BudgetLiveTest do
  use AbakusWeb.ConnCase

  import Phoenix.LiveViewTest

  test "anonymous visitors are sent to the sign-in page", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/")
  end

  describe "signed in" do
    setup :register_and_log_in_user

    test "the start page shows the budget placeholder in the sidebar's layout", %{
      conn: conn,
      user: user
    } do
      {:ok, view, _html} = live(conn, ~p"/")

      assert has_element?(view, "h1", "Budget")
      assert has_element?(view, ~s|aside nav a.active[aria-current=page][href="/"]|, "Budget")
      assert has_element?(view, ~s|aside a[href="/users/settings"]|, "Einstellungen")
      assert has_element?(view, "aside #side-toggle[phx-hook=SideToggle]")

      assert has_element?(
               view,
               ~s|aside #log-out[href="/users/log-out"][data-method=delete][title="#{user.email}"]|,
               "Abmelden"
             )
    end
  end
end
