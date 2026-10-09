defmodule AbakusWeb.ForwardedSSLTest do
  use AbakusWeb.ConnCase, async: true

  import Abakus.UsersFixtures

  alias AbakusWeb.ForwardedSSL

  defp request(headers) do
    headers
    |> Enum.reduce(Plug.Test.conn(:get, "/"), fn {name, value}, conn ->
      put_req_header(conn, name, value)
    end)
    |> ForwardedSSL.call(ForwardedSSL.init([]))
    |> put_resp_cookie("_abakus_key", "value")
    |> send_resp(200, "")
  end

  # Production plugs ForwardedSSL in front of the endpoint; tests run without it.
  defp sign_in(forwarded_proto) do
    {token, _hashed} = generate_user_magic_link_token(user_fixture())

    conn =
      Plug.Test.conn(:post, "/users/log-in", %{"user" => %{"token" => token}})
      |> put_private(:plug_skip_csrf_protection, true)
      |> put_req_header("x-forwarded-proto", forwarded_proto)
      |> ForwardedSSL.call(ForwardedSSL.init([]))
      |> AbakusWeb.Endpoint.call(AbakusWeb.Endpoint.init([]))

    assert redirected_to(conn) == ~p"/"

    for cookie <- get_resp_header(conn, "set-cookie"), into: %{} do
      [name | _] = String.split(cookie, "=", parts: 2)
      {name, cookie |> String.split("; ") |> tl() |> Enum.map(&String.downcase/1)}
    end
  end

  test "a request forwarded as HTTPS gets HSTS and secure cookies" do
    conn = request([{"x-forwarded-proto", "https"}])

    assert conn.scheme == :https
    assert get_resp_header(conn, "strict-transport-security") == ["max-age=31536000"]
    assert conn.resp_cookies["_abakus_key"].secure
  end

  test "a plain HTTP request gets neither" do
    conn = request([])

    assert conn.scheme == :http
    assert get_resp_header(conn, "strict-transport-security") == []
    refute Map.has_key?(conn.resp_cookies["_abakus_key"], :secure)
  end

  test "only the first value of a list of forwarded protocols counts" do
    assert request([{"x-forwarded-proto", "HTTPS, http"}]).scheme == :https
    assert request([{"x-forwarded-proto", "http, https"}]).scheme == :http
  end

  test "behind https the session and remember-me cookies are secure and http-only" do
    cookies = sign_in("https")

    assert Map.keys(cookies) |> Enum.sort() == ["_abakus_key", "_abakus_web_user_remember_me"]

    for {_name, attributes} <- cookies do
      assert "secure" in attributes
      assert "httponly" in attributes
      assert "samesite=lax" in attributes
    end
  end

  test "a plain http request keeps cookies usable over http, still http-only" do
    for {_name, attributes} <- sign_in("http") do
      refute "secure" in attributes
      assert "httponly" in attributes
    end
  end
end
