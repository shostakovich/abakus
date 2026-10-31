defmodule AbakusWeb.DevicesLiveTest do
  use AbakusWeb.ConnCase

  import Phoenix.LiveViewTest
  import Abakus.DevicesFixtures

  alias Abakus.Devices

  setup :register_and_log_in_user

  defp sync(access_token) do
    build_conn()
    |> put_req_header("authorization", "Bearer " <> access_token)
    |> put_req_header("abakus-protocol", "1")
    |> post(~p"/api/sync", %{cursor: 0})
  end

  test "without a signed-in app it says how to sign one in", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/settings/devices")

    assert has_element?(view, "h1", "Geräte")
    assert has_element?(view, "#devices", "Noch keine App angemeldet.")
    assert has_element?(view, "#settings-devices-sidebar[aria-current=page]")
  end

  test "lists each signed-in app with its name, app, sign-in and last sync", %{
    conn: conn,
    scope: scope
  } do
    tokens = sign_in_device(scope, "MacBook")
    sign_in_device(scope, "iPhone")
    assert json_response(sync(tokens.access_token), 200)

    {:ok, view, _html} = live(conn, ~p"/settings/devices")

    assert has_element?(view, "#device-#{tokens.device_id}", "MacBook")
    assert has_element?(view, "#device-#{tokens.device_id}", "Abakus-App")
    assert has_element?(view, "#device-#{tokens.device_id}", "angemeldet")
    assert has_element?(view, "#device-#{tokens.device_id}", "zuletzt synchronisiert")
    assert view |> element("#devices li", "iPhone") |> has_element?()
  end

  describe "scenario: a signed-out device loses access" do
    test "signing out MacBook under Einstellungen → Geräte refuses its next sync", %{
      conn: conn,
      scope: scope
    } do
      tokens = sign_in_device(scope, "MacBook")
      {:ok, view, _html} = live(conn, ~p"/settings/devices")

      confirm_click(view, "#device-#{tokens.device_id}-sign-out", "„MacBook“ abmelden?")

      assert json_response(sync(tokens.access_token), 401)
      refute has_element?(view, "#device-#{tokens.device_id}")
      assert Devices.list_devices(scope) == []
    end
  end

  test "answers 404 to a user who does not own the budget", %{conn: conn} do
    other = Abakus.UsersFixtures.user_fixture()

    assert_error_sent 404, fn -> get(log_in_user(conn, other), ~p"/settings/devices") end
  end
end
