defmodule AbakusWeb.UserSessionControllerTest do
  use AbakusWeb.ConnCase

  import Abakus.UsersFixtures

  alias Abakus.FakeAuthenticator
  alias Abakus.Users
  alias Abakus.WebAuthn

  setup do
    %{user: user_fixture()}
  end

  describe "POST /users/log-in with a magic link" do
    test "signs the user in and remembers the device", %{conn: conn, user: user} do
      {token, _hashed_token} = generate_user_magic_link_token(user)

      conn = post(conn, ~p"/users/log-in", %{"user" => %{"token" => token}})

      assert get_session(conn, :user_token)
      assert conn.resp_cookies["_abakus_web_user_remember_me"]
      assert redirected_to(conn) == ~p"/"

      conn = get(recycle(conn), ~p"/")
      assert html_response(conn, 200) =~ "Budget"
    end

    test "confirms an unconfirmed user", %{conn: conn} do
      user = unconfirmed_user_fixture()
      {token, _hashed_token} = generate_user_magic_link_token(user)

      conn = post(conn, ~p"/users/log-in", %{"user" => %{"token" => token}})

      assert redirected_to(conn) == ~p"/"
      assert Users.get_user!(user.id).confirmed_at
    end

    test "rejects an invalid token", %{conn: conn} do
      conn = post(conn, ~p"/users/log-in", %{"user" => %{"token" => "invalid"}})

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "Der Link ist ungültig oder abgelaufen."

      assert redirected_to(conn) == ~p"/users/log-in"
      refute get_session(conn, :user_token)
    end
  end

  describe "POST /users/log-in with a passkey" do
    setup %{user: user} do
      authenticator = FakeAuthenticator.new()
      passkey_fixture(user, authenticator)
      %{authenticator: authenticator}
    end

    test "signs the user in with the challenge from the session", %{
      conn: conn,
      user: user,
      authenticator: authenticator
    } do
      {conn, challenge} = fetch_challenge(conn)
      assertion = FakeAuthenticator.assertion(authenticator, challenge, user.passkey_handle)

      conn = post(conn, ~p"/users/log-in", %{"passkey" => assertion})

      assert redirected_to(conn) == ~p"/"
      assert {signed_in, _} = Users.get_user_by_session_token(get_session(conn, :user_token))
      assert signed_in.id == user.id
      assert Users.sudo_mode?(signed_in)
    end

    test "uses each challenge only once", %{conn: conn, user: user, authenticator: authenticator} do
      {conn, challenge} = fetch_challenge(conn)

      forged =
        FakeAuthenticator.assertion(authenticator, challenge, user.passkey_handle,
          signer: FakeAuthenticator.new()
        )

      assertion = FakeAuthenticator.assertion(authenticator, challenge, user.passkey_handle)

      conn = post(conn, ~p"/users/log-in", %{"passkey" => forged})
      refute get_session(conn, :user_token)

      conn = conn |> recycle() |> post(~p"/users/log-in", %{"passkey" => assertion})
      refute get_session(conn, :user_token)
      assert redirected_to(conn) == ~p"/users/log-in"
    end

    test "rejects a replay of the assertion with the cookie from before the sign-in", %{
      conn: conn,
      user: user,
      authenticator: authenticator
    } do
      {captured, challenge} = fetch_challenge(conn)
      assertion = FakeAuthenticator.assertion(authenticator, challenge, user.passkey_handle)

      conn = post(captured, ~p"/users/log-in", %{"passkey" => assertion})
      assert get_session(conn, :user_token)

      replay = post(captured, ~p"/users/log-in", %{"passkey" => assertion})
      refute get_session(replay, :user_token)
      assert redirected_to(replay) == ~p"/users/log-in"
    end

    test "rejects a challenge older than the ceremony timeout", %{
      conn: conn,
      user: user,
      authenticator: authenticator
    } do
      challenge = WebAuthn.new_challenge()
      assertion = FakeAuthenticator.assertion(authenticator, challenge, user.passkey_handle)
      issued_at = System.system_time(:millisecond) - WebAuthn.timeout_ms()

      conn =
        conn
        |> init_test_session(%{passkey_login_challenge: {challenge, issued_at}})
        |> post(~p"/users/log-in", %{"passkey" => assertion})

      refute get_session(conn, :user_token)
      assert redirected_to(conn) == ~p"/users/log-in"

      conn =
        build_conn()
        |> init_test_session(%{passkey_login_challenge: {challenge, issued_at + 1_000}})
        |> post(~p"/users/log-in", %{"passkey" => assertion})

      assert get_session(conn, :user_token)
    end

    test "rejects an assertion for another challenge", %{
      conn: conn,
      user: user,
      authenticator: authenticator
    } do
      {conn, _challenge} = fetch_challenge(conn)
      assertion = FakeAuthenticator.assertion(authenticator, "other", user.passkey_handle)

      conn = post(conn, ~p"/users/log-in", %{"passkey" => assertion})

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "Die Anmeldung mit Passkey hat nicht geklappt."

      refute get_session(conn, :user_token)
    end
  end

  test "rejects a token that is not a string", %{conn: conn} do
    assert_error_sent 400, fn ->
      post(conn, ~p"/users/log-in", %{"user" => %{"token" => ["x"]}})
    end
  end

  test "rejects an upload in place of the passkey fields", %{conn: conn} do
    upload = %Plug.Upload{path: __ENV__.file, filename: "passkey.txt"}

    assert_error_sent 400, fn -> post(conn, ~p"/users/log-in", %{"passkey" => upload}) end
  end

  test "DELETE /users/log-out signs the user out", %{conn: conn, user: user} do
    conn = conn |> log_in_user(user) |> delete(~p"/users/log-out")

    assert redirected_to(conn) == ~p"/users/log-in"
    refute get_session(conn, :user_token)
    assert Phoenix.Flash.get(conn.assigns.flash, :info) == "Du bist abgemeldet."
  end

  defp fetch_challenge(conn) do
    conn = post(conn, ~p"/users/passkeys/options")
    {:ok, challenge} = Base.url_decode64(json_response(conn, 200)["challenge"], padding: false)
    {recycle(conn), challenge}
  end
end
