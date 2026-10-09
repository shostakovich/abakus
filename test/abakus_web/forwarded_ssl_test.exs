defmodule AbakusWeb.ForwardedSSLTest do
  use ExUnit.Case, async: true

  import Plug.Conn
  import Plug.Test

  alias AbakusWeb.ForwardedSSL

  defp request(headers) do
    headers
    |> Enum.reduce(conn(:get, "/"), fn {name, value}, conn ->
      put_req_header(conn, name, value)
    end)
    |> ForwardedSSL.call(ForwardedSSL.init([]))
    |> put_resp_cookie("_abakus_key", "value")
    |> send_resp(200, "")
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
end
