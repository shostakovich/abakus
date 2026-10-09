defmodule AbakusWeb.BudgetLiveTest do
  use AbakusWeb.ConnCase

  import Phoenix.LiveViewTest

  test "the start page shows the budget placeholder", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/")

    assert html =~ "<h1"
    assert has_element?(view, "h1", "Budget")
    assert has_element?(view, "#theme-switch[phx-hook=ThemeSwitch]")

    for label <- ["Hell", "Dunkel", "Auto"] do
      assert has_element?(view, "#theme-switch label", label)
    end
  end
end
