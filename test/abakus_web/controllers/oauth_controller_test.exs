defmodule AbakusWeb.OAuthControllerTest do
  use AbakusWeb.ConnCase

  import Abakus.DevicesFixtures

  alias Abakus.Devices.Device
  alias Abakus.Repo

  @callback_uri "local.abakus:/oauth/callback"

  defp authorization(verifier, extra \\ %{}) do
    Map.merge(
      %{
        "response_type" => "code",
        "client_id" => "abakus-apple",
        "redirect_uri" => @callback_uri,
        "code_challenge" => challenge(verifier),
        "code_challenge_method" => "S256",
        "state" => "zustand",
        "device_name" => "MacBook"
      },
      extra
    )
  end

  defp callback_params(conn) do
    [location] = get_resp_header(conn, "location")
    assert String.starts_with?(location, @callback_uri <> "?")
    location |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()
  end

  defp token(params), do: post(build_conn(), ~p"/oauth/token", params)

  defp exchange(code, verifier),
    do:
      token(%{
        "grant_type" => "authorization_code",
        "client_id" => "abakus-apple",
        "redirect_uri" => @callback_uri,
        "code" => code,
        "code_verifier" => verifier
      })

  defp refresh(refresh_token),
    do:
      token(%{
        "grant_type" => "refresh_token",
        "client_id" => "abakus-apple",
        "refresh_token" => refresh_token
      })

  defp sync(access_token) do
    build_conn()
    |> put_req_header("authorization", "Bearer " <> access_token)
    |> put_req_header("abakus-protocol", "1")
    |> post(~p"/api/sync", %{"cursor" => 0, "messages" => []})
  end

  test "the metadata names the endpoints and what they support" do
    conn = get(build_conn(), "/.well-known/oauth-authorization-server")

    assert %{
             "issuer" => "http://localhost:4002",
             "authorization_endpoint" => "http://localhost:4002/oauth/authorize",
             "token_endpoint" => "http://localhost:4002/oauth/token",
             "revocation_endpoint" => "http://localhost:4002/oauth/revoke",
             "response_types_supported" => ["code"],
             "grant_types_supported" => ["authorization_code", "refresh_token"],
             "code_challenge_methods_supported" => ["S256"],
             "token_endpoint_auth_methods_supported" => ["none"]
           } = json_response(conn, 200)
  end

  describe "signed in as the budget owner" do
    setup :register_and_log_in_user

    test "signs an app in end to end: authorize, exchange, refresh twice, reuse signs out", c do
      verifier = verifier()

      page = get(c.conn, ~p"/oauth/authorize?#{authorization(verifier)}")

      assert html_response(page, 200) =~
               "„MacBook“ möchte sich als Abakus-App bei Abakus anmelden."

      decided =
        post(c.conn, ~p"/oauth/authorize", Map.put(authorization(verifier), "decision", "allow"))

      assert %{"code" => code, "state" => "zustand", "iss" => "http://localhost:4002"} =
               callback_params(decided)

      first = json_response(exchange(code, verifier), 200)

      assert %{"token_type" => "Bearer", "expires_in" => 3600, "device_id" => device_id} = first
      assert json_response(sync(first["access_token"]), 200)

      second = json_response(refresh(first["refresh_token"]), 200)
      third = json_response(refresh(second["refresh_token"]), 200)
      assert third["device_id"] == device_id
      assert json_response(sync(third["access_token"]), 200)

      assert json_response(refresh(first["refresh_token"]), 400) == %{"error" => "invalid_grant"}
      assert json_response(sync(third["access_token"]), 401)
      assert json_response(refresh(third["refresh_token"]), 400) == %{"error" => "invalid_grant"}
      assert Repo.get(Device, device_id) == nil
    end

    test "a wrong verifier is refused and uses the code up", c do
      verifier = verifier()

      decided =
        post(c.conn, ~p"/oauth/authorize", Map.put(authorization(verifier), "decision", "allow"))

      %{"code" => code} = callback_params(decided)

      assert json_response(exchange(code, verifier()), 400) == %{"error" => "invalid_grant"}
      assert json_response(exchange(code, verifier), 400) == %{"error" => "invalid_grant"}
    end

    test "cancelling sends the app access_denied and creates no device", c do
      decided =
        post(c.conn, ~p"/oauth/authorize", Map.put(authorization(verifier()), "decision", "deny"))

      assert %{"error" => "access_denied", "state" => "zustand"} = callback_params(decided)
      assert Repo.all(Device) == []
    end

    test "the page's form may lead to the app", c do
      conn = get(c.conn, ~p"/oauth/authorize?#{authorization(verifier())}")

      assert [policy] = get_resp_header(conn, "content-security-policy")
      assert policy =~ "form-action 'self' local.abakus:"
    end

    test "an unknown client or another redirect is answered on the page, not redirected", c do
      for extra <- [%{"client_id" => "fremd"}, %{"redirect_uri" => "https://evil.example/cb"}] do
        conn = get(c.conn, ~p"/oauth/authorize?#{authorization(verifier(), extra)}")
        assert html_response(conn, 400) =~ "Diese App ist bei Abakus nicht bekannt."
      end
    end

    test "a request without PKCE S256 or a device name goes back as invalid_request", c do
      for extra <- [
            %{"code_challenge_method" => "plain"},
            %{"code_challenge" => "kurz"},
            %{"device_name" => " "}
          ] do
        conn = get(c.conn, ~p"/oauth/authorize?#{authorization(verifier(), extra)}")
        assert %{"error" => "invalid_request"} = callback_params(conn)
      end

      conn =
        get(
          c.conn,
          ~p"/oauth/authorize?#{authorization(verifier(), %{"response_type" => "token"})}"
        )

      assert %{"error" => "unsupported_response_type"} = callback_params(conn)
    end

    test "revoking a token signs its device out", c do
      tokens = sign_in_device(c.scope)

      conn =
        post(build_conn(), ~p"/oauth/revoke", %{
          "client_id" => "abakus-apple",
          "token" => tokens.refresh_token
        })

      assert response(conn, 200) == ""
      assert json_response(sync(tokens.access_token), 401)
    end

    test "the token endpoints refuse an unknown client and grant type", c do
      tokens = sign_in_device(c.scope)

      assert json_response(
               token(%{"grant_type" => "refresh_token", "refresh_token" => tokens.refresh_token}),
               401
             ) ==
               %{"error" => "invalid_client"}

      assert json_response(
               token(%{"grant_type" => "password", "client_id" => "abakus-apple"}),
               400
             ) ==
               %{"error" => "unsupported_grant_type"}

      assert json_response(post(build_conn(), ~p"/oauth/revoke", %{"token" => "x"}), 401) ==
               %{"error" => "invalid_client"}
    end
  end

  describe "signed in as someone who does not own the budget" do
    setup :register_and_log_in_user_without_budget

    test "the page says so, and confirming is refused", c do
      verifier = verifier()

      page = get(c.conn, ~p"/oauth/authorize?#{authorization(verifier)}")
      html = html_response(page, 200)
      assert html =~ "Nur wer das Budget führt, kann eine App anmelden."
      refute html =~ ~s(id="authorize-allow")

      decided =
        post(c.conn, ~p"/oauth/authorize", Map.put(authorization(verifier), "decision", "allow"))

      assert %{"error" => "access_denied"} = callback_params(decided)
      assert Repo.all(Device) == []
    end
  end

  test "an anonymous visitor signs in first and comes back to the page" do
    path = ~p"/oauth/authorize?#{authorization(verifier())}"
    conn = get(build_conn(), path)

    assert redirected_to(conn) == ~p"/users/log-in"
    assert get_session(conn, :user_return_to) == path
  end
end
