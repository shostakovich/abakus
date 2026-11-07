defmodule AbakusWeb.Bookkeeping.BusinessAccountsLiveTest do
  use AbakusWeb.ConnCase

  import Phoenix.LiveViewTest
  import Abakus.DomainFixtures
  import Abakus.UsersFixtures

  alias Abakus.Bookkeeping

  describe "a user in Finanzen" do
    setup :register_and_log_in_user

    test "chooses the business accounts, which bring the Buchhaltung", c do
      kontist = account_fixture(name: "Kontist", kind: :tracking)
      giro = account_fixture(name: "Girokonto")

      {:ok, view, _html} = live(c.conn, ~p"/settings/buchhaltung/accounts")
      assert has_element?(view, "#settings-business-accounts-sidebar[aria-current=page]")
      assert_error_sent 404, fn -> get(c.conn, ~p"/buchhaltung") end

      view
      |> form("#business-accounts-form", %{
        "accounts" => %{kontist.id => "true", giro.id => "false"}
      })
      |> render_submit()

      assert_push_event(view, "setzkasten:saved", %{id: "business-accounts-save"})
      assert Bookkeeping.business_account_ids(c.scope) == [kontist.id]
      assert has_element?(view, "#business-account-#{kontist.id}[checked]")

      {:ok, inbox, _html} = live(c.conn, ~p"/buchhaltung")
      assert has_element?(inbox, "#area-switcher", "Buchhaltung")

      view
      |> form("#business-accounts-form", %{"accounts" => %{kontist.id => "false"}})
      |> render_submit()

      assert Bookkeeping.business_account_ids(c.scope) == []
      assert_error_sent 404, fn -> get(c.conn, ~p"/buchhaltung") end
    end
  end

  describe "a user outside Finanzen" do
    setup %{conn: conn} do
      _owner = user_fixture()
      %{conn: log_in_user(conn, user_fixture())}
    end

    test "has no Buchhaltung settings", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/settings/appearance")
      refute has_element?(view, ~s|a[href="/settings/buchhaltung/accounts"]|)

      assert_error_sent 404, fn -> get(conn, ~p"/settings/buchhaltung/accounts") end
      assert_error_sent 404, fn -> get(conn, ~p"/buchhaltung") end
    end
  end
end
