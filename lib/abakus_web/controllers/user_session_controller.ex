defmodule AbakusWeb.UserSessionController do
  use AbakusWeb, :controller

  alias Abakus.Users
  alias Abakus.WebAuthn.Challenges
  alias AbakusWeb.PasskeyController
  alias AbakusWeb.UserAuth

  def create(conn, %{"user" => %{"token" => token}}) when is_binary(token) do
    case Users.login_user_by_magic_link(token) do
      {:ok, user} ->
        conn
        |> put_flash(:info, "Willkommen!")
        |> UserAuth.log_in_user(user)

      _ ->
        conn
        |> put_flash(:error, "Der Link ist ungültig oder abgelaufen.")
        |> redirect(to: ~p"/users/log-in")
    end
  end

  def create(conn, %{"passkey" => %{} = response}) when not is_struct(response) do
    {login, conn} = PasskeyController.pop_login_challenge(conn)
    rp = PasskeyController.relying_party()

    case Challenges.redeem_login(login, &Users.authenticate_passkey(response, &1, rp)) do
      {:ok, user} ->
        UserAuth.log_in_user(conn, user)

      {:error, _reason} ->
        conn
        |> put_flash(:error, "Die Anmeldung mit Passkey hat nicht geklappt.")
        |> redirect(to: ~p"/users/log-in")
    end
  end

  def delete(conn, _params) do
    conn
    |> put_flash(:info, "Du bist abgemeldet.")
    |> UserAuth.log_out_user()
  end
end
