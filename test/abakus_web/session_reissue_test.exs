defmodule AbakusWeb.SessionReissueTest do
  use AbakusWeb.ConnCase

  import Abakus.UsersFixtures

  # A browser keeps the cookies of whichever response came last.
  defp browser(responses) do
    Enum.reduce(responses, build_conn(), fn response, conn ->
      Enum.reduce(response.resp_cookies, conn, fn {name, %{value: value}}, conn ->
        put_req_cookie(conn, name, value)
      end)
    end)
  end

  test "two requests racing with the cookie of a token due for reissue keep the browser signed in" do
    user = user_fixture()
    {link_token, _hashed_token} = generate_user_magic_link_token(user)
    login = post(build_conn(), ~p"/users/log-in", %{"user" => %{"token" => link_token}})
    offset_user_token(get_session(login, :user_token), -8, :day)

    first = get(browser([login]), ~p"/")
    assert first.status == 200
    assert first.resp_cookies["_abakus_web_user_remember_me"]

    second = get(browser([login]), ~p"/")
    assert second.status == 200

    third = get(browser([login, first, second]), ~p"/")
    assert third.status == 200
  end
end
