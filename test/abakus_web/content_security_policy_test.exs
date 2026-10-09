defmodule AbakusWeb.ContentSecurityPolicyTest do
  use AbakusWeb.ConnCase

  defp csp(conn) do
    [policy] = get_resp_header(conn, "content-security-policy")

    Map.new(String.split(policy, "; "), fn directive ->
      [name | sources] = String.split(directive, " ")
      {name, sources}
    end)
  end

  test "pages get a strict policy with a fresh nonce for the theme script", %{conn: conn} do
    conn = get(conn, ~p"/users/log-in")
    html = html_response(conn, 200)
    policy = csp(conn)

    assert ["'self'", "'nonce-" <> nonce] = policy["script-src"]
    nonce = String.trim_trailing(nonce, "'")
    assert byte_size(Base.decode64!(nonce)) == 18

    assert [script] =
             html
             |> LazyHTML.from_document()
             |> LazyHTML.query("script#theme-script[nonce]")
             |> Enum.to_list()

    assert LazyHTML.attribute(script, "nonce") == [nonce]

    assert policy == %{
             "default-src" => ["'self'"],
             "script-src" => ["'self'", "'nonce-#{nonce}'"],
             "style-src" => ["'self'", "https://felt-css.rocu.de"],
             "font-src" => ["'self'"],
             "img-src" => ["'self'", "https://felt-css.rocu.de", "data:"],
             "connect-src" => ["'self'", "ws://localhost:4002"],
             "frame-ancestors" => ["'none'"],
             "object-src" => ["'none'"],
             "base-uri" => ["'self'"],
             "form-action" => ["'self'"]
           }

    [other] = build_conn() |> get(~p"/users/log-in") |> csp() |> Map.fetch!("script-src") |> tl()
    refute other == "'nonce-#{nonce}'"
  end

  test "no inline script runs without the nonce", %{conn: conn} do
    html = conn |> get(~p"/users/log-in") |> html_response(200)
    scripts = html |> LazyHTML.from_document() |> LazyHTML.query("script:not([src])")

    assert Enum.count(scripts) == 1
    assert scripts |> LazyHTML.attribute("nonce") |> Enum.all?(&(&1 != ""))
  end

  test "Phoenix's other secure headers stay", %{conn: conn} do
    conn = get(conn, ~p"/users/log-in")

    assert get_resp_header(conn, "x-content-type-options") == ["nosniff"]
    assert get_resp_header(conn, "referrer-policy") == ["strict-origin-when-cross-origin"]
    assert get_resp_header(conn, "x-permitted-cross-domain-policies") == ["none"]
  end

  # Socket transports (/live) are dispatched before the endpoint's plugs.
  describe "every response but the socket's gets the policy and the secure headers" do
    defp assert_secure(headers) do
      headers = Map.new(headers)
      assert headers["content-security-policy"] =~ "default-src 'self'"
      assert headers["referrer-policy"] == "strict-origin-when-cross-origin"
      assert headers["x-content-type-options"] == "nosniff"
    end

    test "the health check and static files" do
      assert_secure(get(build_conn(), ~p"/up").resp_headers)
      assert_secure(get(build_conn(), ~p"/images/icon.svg").resp_headers)
    end

    test "a missing page, in German" do
      conn = get(build_conn(), "/nope")

      assert html_response(conn, 404) =~ "Seite nicht gefunden"
      assert_secure(conn.resp_headers)
    end

    test "an unacceptable format" do
      {406, headers, _body} =
        assert_error_sent(406, fn ->
          build_conn() |> put_req_header("accept", "application/xml") |> get(~p"/users/log-in")
        end)

      assert_secure(headers)
    end

    test "a missing CSRF token" do
      {403, headers, body} =
        assert_error_sent(403, fn ->
          build_conn()
          |> put_private(:plug_skip_csrf_protection, false)
          |> post(~p"/users/log-in", %{"user" => %{"token" => "x"}})
        end)

      assert_secure(headers)
      assert body =~ "Zugriff verweigert"
    end

    test "a static path that is refused" do
      {400, headers, _body} =
        assert_error_sent(400, fn -> get(build_conn(), "/assets/%2e%2e/x") end)

      assert_secure(headers)
    end

    test "a body that does not parse" do
      {400, headers, _body} =
        assert_error_sent(400, fn ->
          build_conn()
          |> put_req_header("content-type", "application/json")
          |> post(~p"/users/passkeys/options", "{")
        end)

      assert_secure(headers)
    end
  end

  test "behind https the socket connects over wss to the public host" do
    assert AbakusWeb.ContentSecurityPolicy.policy("n", "https://abakus.example.org") =~
             "; connect-src 'self' wss://abakus.example.org;"

    assert AbakusWeb.ContentSecurityPolicy.policy("n", "http://localhost:4021") =~
             "; connect-src 'self' ws://localhost:4021;"
  end
end
