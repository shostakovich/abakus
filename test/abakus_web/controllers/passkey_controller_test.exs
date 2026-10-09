defmodule AbakusWeb.PasskeyControllerTest do
  use AbakusWeb.ConnCase

  import Abakus.UsersFixtures

  alias Abakus.FakeAuthenticator
  alias Abakus.Users
  alias Abakus.WebAuthn.Challenges
  alias AbakusWeb.PasskeyController

  test "the relying party is the endpoint's host and origin" do
    assert PasskeyController.relying_party() == FakeAuthenticator.relying_party()
  end

  test "POST /users/passkeys/options needs no sign-in", %{conn: conn} do
    options = conn |> post(~p"/users/passkeys/options") |> json_response(200)

    assert options["rpId"] == "localhost"
    assert options["allowCredentials"] == []
  end

  test "anonymous sign-in options store nothing on the server" do
    1..10_000
    |> Task.async_stream(fn _ ->
      build_conn() |> post(~p"/users/passkeys/options") |> json_response(200)
    end)
    |> Stream.run()

    assert Challenges.size() == 0
  end

  describe "registering a passkey" do
    setup :register_and_log_in_user

    test "stores the passkey under its name", %{conn: conn, user: user} do
      conn = post(conn, ~p"/users/settings/passkeys/options", %{name: "Mac"})
      options = json_response(conn, 200)
      assert options["user"]["id"] == FakeAuthenticator.encode(user.passkey_handle)

      {:ok, challenge} = Base.url_decode64(options["challenge"], padding: false)
      response = FakeAuthenticator.registration(FakeAuthenticator.new(:eddsa), challenge)

      conn =
        conn |> recycle() |> post(~p"/users/settings/passkeys", %{passkey: response, name: "Mac"})

      assert %{"id" => id} = json_response(conn, 200)
      assert [%{id: ^id, name: "Mac", algorithm: -8}] = Users.list_passkeys(user)
    end

    test "fails without a challenge in the session", %{conn: conn, user: user} do
      response = FakeAuthenticator.registration(FakeAuthenticator.new(), "challenge")
      conn = post(conn, ~p"/users/settings/passkeys", %{passkey: response, name: "Mac"})

      assert json_response(conn, 422)["error"] == "Der Passkey konnte nicht geprüft werden."
      assert Users.list_passkeys(user) == []
    end

    test "asks for a name before the ceremony", %{conn: conn} do
      for params <- [%{}, %{name: ""}, %{name: "   "}, %{name: String.duplicate("x", 61)}] do
        conn = post(conn, ~p"/users/settings/passkeys/options", params)

        assert json_response(conn, 422)["error"] ==
                 "Bitte gib dem Passkey einen Namen (höchstens 60 Zeichen)."
      end
    end

    test "refuses control characters in the name", %{conn: conn, user: user} do
      message = "Der Name darf keine Steuer- oder unsichtbaren Zeichen enthalten."

      conn =
        post(conn, ~p"/users/settings/passkeys/options", %{name: "Mac\r\nBcc: a@example.com"})

      assert json_response(conn, 422)["error"] == message

      conn = post(conn, ~p"/users/settings/passkeys/options", %{name: "Mac"})
      {:ok, challenge} = Base.url_decode64(json_response(conn, 200)["challenge"], padding: false)
      response = FakeAuthenticator.registration(FakeAuthenticator.new(), challenge)

      conn =
        conn
        |> recycle()
        |> post(~p"/users/settings/passkeys", %{passkey: response, name: "Mac\nmini"})

      assert json_response(conn, 422)["error"] == message
      assert Users.list_passkeys(user) == []
    end

    test "asks for a name when registering", %{conn: conn} do
      conn = post(conn, ~p"/users/settings/passkeys/options", %{name: "Mac"})
      {:ok, challenge} = Base.url_decode64(json_response(conn, 200)["challenge"], padding: false)
      response = FakeAuthenticator.registration(FakeAuthenticator.new(), challenge)

      conn =
        conn |> recycle() |> post(~p"/users/settings/passkeys", %{passkey: response, name: ""})

      assert json_response(conn, 422)["error"] =~ "Namen"
    end

    test "says so when the passkey is already registered", %{conn: conn} do
      authenticator = FakeAuthenticator.new()
      passkey_fixture(user_fixture(), authenticator)

      conn = post(conn, ~p"/users/settings/passkeys/options", %{name: "Mac"})
      {:ok, challenge} = Base.url_decode64(json_response(conn, 200)["challenge"], padding: false)
      response = FakeAuthenticator.registration(authenticator, challenge)

      conn =
        conn |> recycle() |> post(~p"/users/settings/passkeys", %{passkey: response, name: "Mac"})

      assert json_response(conn, 422)["error"] == "Dieser Passkey ist schon hinterlegt."
    end

    test "keeps one open challenge per session", %{conn: conn} do
      conn = post(conn, ~p"/users/settings/passkeys/options", %{name: "Mac"})

      Enum.reduce(1..5, conn, fn _, conn ->
        conn |> recycle() |> post(~p"/users/settings/passkeys/options", %{name: "Mac"})
      end)

      assert Challenges.size() == 1
    end

    test "answers 503 while too many registrations are open", %{conn: conn} do
      Stream.repeatedly(fn -> Challenges.issue_registration(0) end)
      |> Enum.find(&(&1 == {:error, :busy}))

      conn = post(conn, ~p"/users/settings/passkeys/options", %{name: "Mac"})

      assert json_response(conn, 503)["error"] ==
               "Gerade sind zu viele Anfragen offen, bitte gleich noch einmal."
    end

    test "rejects a challenge id the server did not issue", %{conn: conn, user: user} do
      response = FakeAuthenticator.registration(FakeAuthenticator.new(), "challenge")

      conn =
        conn
        |> init_test_session(%{passkey_registration_challenge_id: "made-up"})
        |> post(~p"/users/settings/passkeys", %{passkey: response, name: "Mac"})

      assert json_response(conn, 422)["error"] == "Der Passkey konnte nicht geprüft werden."
      assert Users.list_passkeys(user) == []
    end

    test "rejects an upload in place of the passkey fields", %{conn: conn} do
      upload = %Plug.Upload{path: __ENV__.file, filename: "passkey.txt"}
      conn = post(conn, ~p"/users/settings/passkeys", %{passkey: upload, name: "Mac"})

      assert json_response(conn, 422)["error"] == "Unvollständige Anfrage."
    end

    @tag signed_in_minutes_ago: 11
    test "needs a recent sign-in, and comes back to the settings after it", %{conn: conn} do
      conn = post(conn, ~p"/users/settings/passkeys/options", %{name: "Mac"})

      assert json_response(conn, 403) == %{"error" => "sudo"}
      assert get_session(conn, :user_return_to) == ~p"/users/settings"
    end

    # Signed in 6 minutes ago: sudo mode ends before the 5-minute ceremony could.
    @tag signed_in_minutes_ago: 6
    test "needs the ceremony timeout left in sudo mode", %{conn: conn} do
      conn = post(conn, ~p"/users/settings/passkeys/options", %{name: "Mac"})

      assert json_response(conn, 403) == %{"error" => "sudo"}
    end

    @tag signed_in_minutes_ago: 4
    test "starts a ceremony with enough of sudo mode left", %{conn: conn} do
      conn = post(conn, ~p"/users/settings/passkeys/options", %{name: "Mac"})

      assert json_response(conn, 200)["challenge"]
    end
  end

  test "registration answers 401 without a session, so the hook can reload", %{conn: conn} do
    for path <- [~p"/users/settings/passkeys/options", ~p"/users/settings/passkeys"] do
      conn = post(conn, path)

      assert json_response(conn, 401) == %{"error" => "session"}
    end
  end
end
