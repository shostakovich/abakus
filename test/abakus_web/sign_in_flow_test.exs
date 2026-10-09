defmodule AbakusWeb.SignInFlowTest do
  use AbakusWeb.ConnCase

  import Abakus.UsersFixtures
  import Phoenix.LiveViewTest

  alias Abakus.FakeAuthenticator
  alias Abakus.Users

  test "invite, magic link, new passkey, sign out, sign in with the passkey" do
    {:ok, _user} = Users.invite_user("neu@example.com", &AbakusWeb.UserAuth.magic_link_url/1)
    assert_received {:email, %{subject: "Abakus: Einladung", text_body: body}}
    [_link, token] = Regex.run(~r{http://localhost:4002/users/log-in/(\S+)}, body)

    conn = get(build_conn(), ~p"/users/log-in/#{token}")
    assert html_response(conn, 200) =~ "neu@example.com"

    conn = post(conn, ~p"/users/log-in", %{"user" => %{"token" => token}})
    assert redirected_to(conn) == ~p"/"

    conn = post(conn, ~p"/users/settings/passkeys/options", %{name: "Laptop"})
    options = json_response(conn, 200)
    user_handle = decode(options["user"]["id"])
    authenticator = FakeAuthenticator.new()
    response = FakeAuthenticator.registration(authenticator, decode(options["challenge"]))

    conn = post(conn, ~p"/users/settings/passkeys", %{name: "Laptop", passkey: response})
    assert %{"id" => _id} = json_response(conn, 200)
    assert_received {:email, %{subject: "Abakus: neuer Passkey „Laptop“"}}

    conn = delete(conn, ~p"/users/log-out")
    assert redirected_to(conn) == ~p"/users/log-in"
    assert conn |> get(~p"/") |> redirected_to() == ~p"/users/log-in"

    conn = post(conn, ~p"/users/passkeys/options")
    challenge = decode(json_response(conn, 200)["challenge"])
    assertion = FakeAuthenticator.assertion(authenticator, challenge, user_handle)

    conn = post(conn, ~p"/users/log-in", %{"passkey" => assertion})
    assert redirected_to(conn) == ~p"/"

    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "Budget"
    assert {user, _inserted_at} = Users.get_user_by_session_token(get_session(conn, :user_token))
    assert user.email == "neu@example.com"
  end

  test "a tab rendered before the same user signs in again still connects" do
    user = user_fixture()
    tab = build_conn() |> log_in_user(user) |> get(~p"/")
    old_topic = "users_sessions:#{Base.url_encode64(get_session(tab, :user_token))}"
    AbakusWeb.Endpoint.subscribe(old_topic)

    {token, _hashed_token} = generate_user_magic_link_token(user)
    conn = post(tab, ~p"/users/log-in", %{"user" => %{"token" => token}})
    assert redirected_to(conn) == ~p"/"

    refute_received %Phoenix.Socket.Broadcast{topic: ^old_topic, event: "disconnect"}
    assert {:ok, _view, html} = live(tab)
    assert html =~ "Budget"
  end

  defp decode(value), do: Base.url_decode64!(value, padding: false)
end
