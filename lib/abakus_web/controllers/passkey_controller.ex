defmodule AbakusWeb.PasskeyController do
  @moduledoc """
  The server side of the passkey hooks: options for the browser, and the registration of a new
  passkey. A sign-in challenge lives in the signed session, a registration challenge on the
  server (`Abakus.WebAuthn.Challenges`) under an id in the session; the session's challenge is
  dropped on its first use and holds only within the ceremony timeout. Signing in with a passkey
  posts to `UserSessionController`.
  """
  use AbakusWeb, :controller

  alias Abakus.Users
  alias Abakus.Users.Passkey
  alias Abakus.WebAuthn
  alias Abakus.WebAuthn.Challenges

  @unverified "Der Passkey konnte nicht geprüft werden."

  def relying_party do
    %{
      id: AbakusWeb.Endpoint.host(),
      origin: AbakusWeb.Endpoint.url(),
      name: "Abakus"
    }
  end

  @doc "Takes the sign-in challenge out of the session, for `Challenges.redeem_login/3`."
  def pop_login_challenge(conn) do
    {get_session(conn, :passkey_login_challenge), delete_session(conn, :passkey_login_challenge)}
  end

  def authentication_options(conn, _params) do
    {challenge, _issued_at} = login = Challenges.issue_login()

    conn
    |> put_session(:passkey_login_challenge, login)
    |> json(WebAuthn.authentication_options(relying_party(), challenge))
  end

  # Takes the registration challenge out of the store and its id out of the session; `nil` once
  # it was used or is older than the ceremony timeout.
  defp pop_registration_challenge(conn) do
    id = get_session(conn, :passkey_registration_challenge_id)
    user_id = conn.assigns.current_scope.user.id

    {Challenges.take_registration(id, user_id),
     delete_session(conn, :passkey_registration_challenge_id)}
  end

  # Replaces the session's open challenge, so a session holds at most one.
  defp put_registration_challenge(conn) do
    {_challenge, conn} = pop_registration_challenge(conn)

    with {:ok, {id, challenge}} <-
           Challenges.issue_registration(conn.assigns.current_scope.user.id) do
      {:ok, challenge, put_session(conn, :passkey_registration_challenge_id, id)}
    end
  end

  def registration_options(conn, params) do
    user = conn.assigns.current_scope.user

    cond do
      # The hook sends the user to sign in again, and the sign-in back here.
      not sudo_mode_for_ceremony?(user) ->
        conn
        |> put_session(:user_return_to, ~p"/users/settings")
        |> put_status(:forbidden)
        |> json(%{error: "sudo"})

      message = Passkey.name_error(params["name"]) ->
        unprocessable(conn, message)

      true ->
        case put_registration_challenge(conn) do
          {:ok, challenge, conn} ->
            json(conn, Users.passkey_registration_options(user, relying_party(), challenge))

          {:error, :busy} ->
            busy(conn)
        end
    end
  end

  # Checked before the browser asks for the passkey, so the ceremony can finish in sudo mode.
  defp sudo_mode_for_ceremony?(user) do
    Users.sudo_mode?(user, Users.sudo_mode_minutes() - div(WebAuthn.timeout_ms(), 60_000))
  end

  def create(conn, %{"passkey" => %{} = response, "name" => name})
      when not is_struct(response) do
    user = conn.assigns.current_scope.user
    {challenge, conn} = pop_registration_challenge(conn)

    with true <- is_binary(challenge) and Users.sudo_mode?(user),
         {:ok, passkey} <-
           Users.register_passkey(user, response, challenge, relying_party(), name) do
      json(conn, %{id: passkey.id})
    else
      {:error, %Ecto.Changeset{errors: errors}} ->
        cond do
          Keyword.has_key?(errors, :credential_id) ->
            unprocessable(conn, "Dieser Passkey ist schon hinterlegt.")

          message = Passkey.name_error(name) ->
            unprocessable(conn, message)

          true ->
            unprocessable(conn, @unverified)
        end

      _ ->
        unprocessable(conn, @unverified)
    end
  end

  def create(conn, _params), do: unprocessable(conn, "Unvollständige Anfrage.")

  defp busy(conn) do
    conn
    |> put_status(:service_unavailable)
    |> json(%{error: "Gerade sind zu viele Anfragen offen, bitte gleich noch einmal."})
  end

  defp unprocessable(conn, message),
    do: conn |> put_status(:unprocessable_entity) |> json(%{error: message})
end
