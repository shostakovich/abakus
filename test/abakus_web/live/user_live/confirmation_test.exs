defmodule AbakusWeb.UserLive.ConfirmationTest do
  use AbakusWeb.ConnCase

  import Phoenix.LiveViewTest
  import Abakus.UsersFixtures

  alias Abakus.Users

  setup do
    user = unconfirmed_user_fixture()
    token = extract_user_token(&Users.deliver_login_instructions(user, &1))
    %{user: user, token: token}
  end

  test "signs in and confirms the user once", %{conn: conn, user: user, token: token} do
    {:ok, lv, html} = live(conn, ~p"/users/log-in/#{token}")
    assert html =~ user.email

    form = form(lv, "#login-form", %{"user" => %{"token" => token}})
    render_submit(form)
    conn = follow_trigger_action(form, conn)

    assert Phoenix.Flash.get(conn.assigns.flash, :info) == "Willkommen!"
    assert redirected_to(conn) == ~p"/"
    assert get_session(conn, :user_token)
    assert Users.get_user!(user.id).confirmed_at

    {:ok, _lv, html} =
      build_conn()
      |> live(~p"/users/log-in/#{token}")
      |> follow_redirect(build_conn(), ~p"/users/log-in")

    assert html =~ "Der Link ist ungültig oder abgelaufen."
  end

  # At debug level, which includes the request lines at info.
  test "keeps the token out of the log", %{conn: conn, token: token} do
    level = Logger.level()
    Logger.configure(level: :debug)
    on_exit(fn -> Logger.configure(level: level) end)

    log =
      ExUnit.CaptureLog.capture_log([level: :debug], fn ->
        get(conn, ~p"/users/log-in/#{token}")
        {:ok, _lv, _html} = live(build_conn(), ~p"/users/log-in/#{token}")
        post(build_conn(), ~p"/users/log-in", %{"user" => %{"token" => token}})
      end)

    assert log =~ "POST /users/log-in"
    assert log =~ ~s("token" => "[FILTERED]")
    refute log =~ token
  end

  test "rejects an unknown token", %{conn: conn} do
    {:ok, _lv, html} =
      conn |> live(~p"/users/log-in/invalid") |> follow_redirect(conn, ~p"/users/log-in")

    assert html =~ "Der Link ist ungültig oder abgelaufen."
  end
end
