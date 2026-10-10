defmodule AbakusWeb.UserLive.SettingsTest do
  use AbakusWeb.ConnCase

  alias Abakus.Users
  import Phoenix.LiveViewTest
  import Abakus.UsersFixtures

  describe "Settings page" do
    test "renders settings page", %{conn: conn} do
      {:ok, lv, html} =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/users/settings")

      assert html =~ "E-Mail ändern"
      assert html =~ "Passkey hinzufügen"
      refute html =~ "Passwort"
      assert has_element?(lv, ~s|aside nav a.active[aria-current=page][href="/users/settings"]|)
    end

    test "chooses the theme under Aussehen", %{conn: conn} do
      {:ok, lv, _html} = conn |> log_in_user(user_fixture()) |> live(~p"/users/settings")

      assert has_element?(lv, "#appearance #theme-switch[phx-hook=ThemeSwitch]")

      for label <- ["Hell", "Dunkel", "Auto"] do
        assert has_element?(lv, "#theme-switch label", label)
      end
    end

    test "redirects if user is not logged in", %{conn: conn} do
      assert {:error, redirect} = live(conn, ~p"/users/settings")

      assert {:redirect, %{to: path, flash: flash}} = redirect
      assert path == ~p"/users/log-in"
      assert %{"error" => "Bitte melde dich an."} = flash
    end

    test "redirects if user is not in sudo mode", %{conn: conn} do
      {:ok, conn} =
        conn
        |> log_in_user(user_fixture(),
          token_authenticated_at: DateTime.add(DateTime.utc_now(), -11, :minute)
        )
        |> live(~p"/users/settings")
        |> follow_redirect(conn, ~p"/users/log-in")

      assert conn.resp_body =~ "Bitte melde dich für diese Änderung erneut an."
    end
  end

  describe "update email form" do
    setup %{conn: conn} do
      user = user_fixture()
      %{conn: log_in_user(conn, user), user: user}
    end

    test "updates the user email", %{conn: conn, user: user} do
      new_email = unique_user_email()

      {:ok, lv, _html} = live(conn, ~p"/users/settings")

      result =
        lv
        |> form("#email-form", %{
          "user" => %{"email" => new_email}
        })
        |> render_submit()

      assert result =~ "Wir haben einen Bestätigungslink"
      assert Users.get_user_by_email(user.email)
    end

    test "renders errors with invalid data (phx-change)", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/settings")

      result =
        lv
        |> element("#email-form")
        |> render_change(%{
          "action" => "update_email",
          "user" => %{"email" => "with spaces"}
        })

      assert result =~ "E-Mail ändern"
      assert result =~ "braucht ein @ und keine Leerzeichen"
    end

    test "renders errors with invalid data (phx-submit)", %{conn: conn, user: user} do
      {:ok, lv, _html} = live(conn, ~p"/users/settings")

      result =
        lv
        |> form("#email-form", %{
          "user" => %{"email" => user.email}
        })
        |> render_submit()

      assert result =~ "E-Mail ändern"
      assert result =~ "ist unverändert"
    end
  end

  describe "confirm email" do
    setup %{conn: conn} do
      user = user_fixture()
      email = unique_user_email()

      token =
        extract_user_token(fn url ->
          Users.deliver_user_update_email_instructions(%{user | email: email}, user.email, url)
        end)

      %{conn: log_in_user(conn, user), token: token, email: email, user: user}
    end

    test "updates the user email once", %{conn: conn, user: user, token: token, email: email} do
      {:error, redirect} = live(conn, ~p"/users/settings/confirm-email/#{token}")

      assert {:live_redirect, %{to: path, flash: flash}} = redirect
      assert path == ~p"/users/settings"
      assert %{"info" => message} = flash
      assert message == "Die E-Mail-Adresse ist geändert."
      refute Users.get_user_by_email(user.email)
      assert Users.get_user_by_email(email)

      # use confirm token again
      {:error, redirect} = live(conn, ~p"/users/settings/confirm-email/#{token}")
      assert {:live_redirect, %{to: path, flash: flash}} = redirect
      assert path == ~p"/users/settings"
      assert %{"error" => message} = flash
      assert message == "Der Link ist ungültig oder abgelaufen."
    end

    # At debug level, which includes the request lines at info.
    test "keeps the token out of the log", %{conn: conn, token: token} do
      level = Logger.level()
      Logger.configure(level: :debug)
      on_exit(fn -> Logger.configure(level: level) end)

      log =
        ExUnit.CaptureLog.capture_log([level: :debug], fn ->
          get(conn, ~p"/users/settings/confirm-email/#{token}")
          {:error, _redirect} = live(conn, ~p"/users/settings/confirm-email/#{token}")
        end)

      assert log =~ "AbakusWeb.UserLive.Settings"
      refute log =~ token
    end

    test "does not update email with invalid token", %{conn: conn, user: user} do
      {:error, redirect} = live(conn, ~p"/users/settings/confirm-email/oops")
      assert {:live_redirect, %{to: path, flash: flash}} = redirect
      assert path == ~p"/users/settings"
      assert %{"error" => message} = flash
      assert message == "Der Link ist ungültig oder abgelaufen."
      assert Users.get_user_by_email(user.email)
    end

    test "after the sudo window, changes the email once the user signed in again", %{
      user: user,
      token: token,
      email: email
    } do
      path = ~p"/users/settings/confirm-email/#{token}"
      signed_in_at = DateTime.add(DateTime.utc_now(), -11, :minute)

      conn = build_conn() |> log_in_user(user, token_authenticated_at: signed_in_at) |> get(path)

      assert redirected_to(conn) == ~p"/users/log-in"
      conn = get(conn, ~p"/users/log-in")
      assert html_response(conn, 200) =~ "Bitte melde dich für diese Änderung erneut an."

      {link_token, _hashed_token} = generate_user_magic_link_token(user)
      conn = post(conn, ~p"/users/log-in", %{"user" => %{"token" => link_token}})
      assert redirected_to(conn) == path

      assert {:error, {:live_redirect, %{to: "/users/settings", flash: flash}}} =
               live(recycle(conn), path)

      assert flash["info"] == "Die E-Mail-Adresse ist geändert."
      assert Users.get_user_by_email(email).id == user.id
    end

    test "redirects if user is not logged in", %{token: token} do
      conn = build_conn()
      {:error, redirect} = live(conn, ~p"/users/settings/confirm-email/#{token}")
      assert {:redirect, %{to: path, flash: flash}} = redirect
      assert path == ~p"/users/log-in"
      assert %{"error" => message} = flash
      assert message == "Bitte melde dich an."
    end
  end

  describe "passkeys" do
    setup :register_and_log_in_user

    test "lists, refreshes and deletes the user's passkeys", %{conn: conn, user: user} do
      {:ok, lv, html} = live(conn, ~p"/users/settings")
      assert html =~ "Noch kein Passkey hinterlegt."
      assert has_element?(lv, "#passkey-register[phx-hook=PasskeyRegister]")
      # The hook owns the form: a re-render (e.g. for an error flash) keeps the typed name.
      assert has_element?(lv, "#passkey-register[phx-update=ignore]")

      passkey = passkey_fixture(user)
      html = render_hook(lv, "passkey_registered", %{})
      assert html =~ "Passkey hinzugefügt."
      assert has_element?(lv, "#passkey-#{passkey.id}", "Testgerät")

      lv |> element("#passkey-#{passkey.id} button", "Löschen") |> render_click()
      refute has_element?(lv, "#passkey-#{passkey.id}")
      assert Abakus.Users.list_passkeys(user) == []
    end

    test "cannot delete another user's passkey", %{conn: conn} do
      passkey = passkey_fixture(user_fixture())
      {:ok, lv, _html} = live(conn, ~p"/users/settings")

      assert render_click(lv, "delete_passkey", %{"id" => passkey.id}) =~
               "Den Passkey gibt es nicht mehr."

      assert Abakus.Repo.get(Abakus.Users.Passkey, passkey.id)
    end
  end

  describe "passkey ids from the client" do
    setup :register_and_log_in_user

    test "ignores one that is not a number", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/settings")

      assert render_click(lv, "delete_passkey", %{"id" => "abc"}) =~
               "Den Passkey gibt es nicht mehr."
    end
  end

  describe "a page left open" do
    # The page mounts in sudo mode; then the window closes or the session ends elsewhere.
    setup %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)
      token = get_session(conn, :user_token)
      {:ok, lv, _html} = live(conn, ~p"/users/settings")
      %{lv: lv, user: user, conn: conn, token: token}
    end

    defp close_sudo_window(token),
      do: override_token_authenticated_at(token, DateTime.add(DateTime.utc_now(), -11, :minute))

    test "cannot delete a passkey past the sudo window, and comes back after signing in",
         %{lv: lv, user: user, conn: conn} = ctx do
      passkey = passkey_fixture(user)
      close_sudo_window(ctx.token)

      assert {:error, {:redirect, %{to: "/users/settings"}}} =
               render_click(lv, "delete_passkey", %{"id" => passkey.id})

      assert [_passkey] = Users.list_passkeys(user)

      conn = get(conn, ~p"/users/settings")
      assert redirected_to(conn) == ~p"/users/log-in"
      conn = get(conn, ~p"/users/log-in")
      assert html_response(conn, 200) =~ "Bitte melde dich für diese Änderung erneut an."

      {link_token, _hashed_token} = generate_user_magic_link_token(user)
      conn = post(conn, ~p"/users/log-in", %{"user" => %{"token" => link_token}})
      assert redirected_to(conn) == ~p"/users/settings"

      {:ok, lv, _html} = live(recycle(conn), ~p"/users/settings")
      lv |> element("#passkey-#{passkey.id} button", "Löschen") |> render_click()
      assert Users.list_passkeys(user) == []
    end

    test "cannot change the email past the sudo window", %{lv: lv, token: token} do
      close_sudo_window(token)

      assert {:error, {:redirect, %{to: "/users/settings"}}} =
               lv
               |> form("#email-form", %{"user" => %{"email" => unique_user_email()}})
               |> render_submit()

      refute_received {:email, %{subject: "Abakus: neue E-Mail-Adresse bestätigen"}}
    end

    test "cannot change anything once the session is gone", %{lv: lv, user: user, token: token} do
      passkey = passkey_fixture(user)
      Users.delete_user_session_token(token)

      assert {:error, {:redirect, %{to: "/users/settings"}}} =
               render_click(lv, "delete_passkey", %{"id" => passkey.id})

      assert [_passkey] = Users.list_passkeys(user)
    end
  end
end
