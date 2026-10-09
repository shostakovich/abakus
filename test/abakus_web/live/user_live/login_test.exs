defmodule AbakusWeb.UserLive.LoginTest do
  use AbakusWeb.ConnCase

  import Phoenix.LiveViewTest
  import Abakus.UsersFixtures

  test "offers a passkey and a magic link, no password or sign-up", %{conn: conn} do
    {:ok, lv, html} = live(conn, ~p"/users/log-in")

    assert has_element?(lv, "#passkey-login[phx-hook=PasskeyLogin]")
    assert has_element?(lv, "#passkey-form[action='/users/log-in']")
    assert has_element?(lv, "#login-form input[type=email]")
    refute html =~ "Passwort"
    refute html =~ "Registrieren"
  end

  @answer "Wenn die Adresse bei uns bekannt ist, kommt gleich ein Anmeldelink."

  defp request_link(conn, email) do
    {:ok, lv, _html} = live(conn, ~p"/users/log-in")

    {:ok, _lv, html} =
      lv
      |> form("#login-form", user: %{email: email})
      |> render_submit()
      |> follow_redirect(conn, ~p"/users/log-in")

    await_background_tasks()
    html
  end

  test "sends a magic link to a known address", %{conn: conn} do
    user = user_fixture()
    assert_received {:email, _fixture_mail}

    assert request_link(conn, user.email) =~ @answer

    assert_received {:email, %{subject: "Abakus: Anmeldelink", text_body: body}}
    assert body =~ "http://localhost:4002/users/log-in/"

    assert Abakus.Repo.get_by!(Abakus.Users.UserToken, user_id: user.id).context ==
             "login"
  end

  test "answers the same for an unknown address", %{conn: conn} do
    assert request_link(conn, "unknown@example.com") =~ @answer
    refute_received {:email, _}
  end

  test "answers the same once a limit is reached, without a mail", %{conn: conn} do
    user = user_fixture()
    assert_received {:email, _fixture_mail}

    for _ <- 1..3, do: assert(request_link(conn, user.email) =~ @answer)
    for _ <- 1..3, do: assert_received({:email, _})

    {html, log} =
      ExUnit.CaptureLog.with_log(fn -> request_link(conn, String.upcase(user.email)) end)

    assert html =~ @answer
    assert log =~ "limit per address reached"
    refute_received {:email, _}
  end

  test "ignores an email that is not a string", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/users/log-in")

    log =
      ExUnit.CaptureLog.capture_log(fn ->
        render_submit(lv, "send_link", %{"user" => %{"email" => ["a@example.com"]}})
        await_background_tasks()
      end)

    assert log == ""
    refute_received {:email, _}
  end

  test "drops link requests while too many are in progress, and says so once", %{conn: conn} do
    user = user_fixture()
    assert_received {:email, _fixture_mail}

    blockers =
      for _ <- 1..50 do
        {:ok, pid} =
          Task.Supervisor.start_child(Abakus.TaskSupervisor, fn ->
            receive do
              :stop -> :ok
            end
          end)

        pid
      end

    on_exit(fn -> Enum.each(blockers, &send(&1, :stop)) end)

    log =
      ExUnit.CaptureLog.capture_log(fn ->
        for _ <- 1..2 do
          {:ok, lv, _html} = live(conn, ~p"/users/log-in")

          {:ok, _lv, html} =
            lv
            |> form("#login-form", user: %{email: user.email})
            |> render_submit()
            |> follow_redirect(conn, ~p"/users/log-in")

          assert html =~ @answer
        end
      end)

    Enum.each(blockers, &send(&1, :stop))
    await_background_tasks()

    assert [_once] = Regex.scan(~r/Login links dropped/, log)
    refute_received {:email, _}
  end

  test "shows passkey errors from the hook", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/users/log-in")

    assert render_hook(lv, "passkey_error", %{"message" => "Kaputt."}) =~ "Kaputt."
  end

  test "asks a signed-in user to sign in again for sudo mode", %{conn: conn} do
    user = user_fixture()
    {:ok, _lv, html} = conn |> log_in_user(user) |> live(~p"/users/log-in")

    assert html =~ "Für Änderungen an deiner Anmeldung meldest du dich bitte noch einmal an."
  end
end
