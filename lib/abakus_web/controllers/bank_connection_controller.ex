defmodule AbakusWeb.BankConnectionController do
  @moduledoc """
  The way to the bank and back when connecting it. `authorize` keeps the consent's random state in the session and
  sends the user to the bank; it takes them from an encrypted, short-lived link of the Bankverbindungen tab, as a
  LiveView cannot write the session and a form may not lead off-site (CSP `form-action`). `callback` is where the
  bank sends them back: only with the session's state does its code connect the bank, or renew the consent of the
  connection it was started for.
  """
  use AbakusWeb, :controller

  alias Abakus.{BankSync, Format}

  @salt "bank-sync authorize"
  @max_age 5 * 60

  @doc "The link that sends the scope's user to the bank's `url` for the consent `auth` of `BankSync.authorize/3`."
  def authorize_path(scope, url, auth) do
    token =
      Phoenix.Token.encrypt(AbakusWeb.Endpoint, @salt, %{
        user_id: scope.user.id,
        url: url,
        auth: auth
      })

    ~p"/budget/bank-connections/authorize?#{[token: token]}"
  end

  def authorize(conn, params) do
    user_id = conn.assigns.current_scope.user.id

    case decrypt(params["token"]) do
      {:ok, %{user_id: ^user_id, url: url, auth: auth}} ->
        conn |> put_session(:bank_auth, auth) |> redirect(external: url)

      _invalid ->
        back(conn, "Der Weg zur Bank ist abgelaufen. Bitte die Bank noch einmal wählen.")
    end
  end

  defp decrypt(token) when is_binary(token),
    do: Phoenix.Token.decrypt(AbakusWeb.Endpoint, @salt, token, max_age: @max_age)

  defp decrypt(_missing), do: {:error, :missing}

  def callback(conn, params) do
    auth = get_session(conn, :bank_auth)
    conn = delete_session(conn, :bank_auth)

    cond do
      not same_state?(auth, params["state"]) ->
        back(
          conn,
          "Die Rückkehr von der Bank passt zu keiner begonnenen Verbindung. Bitte neu verbinden."
        )

      is_binary(params["code"]) ->
        connect(conn, auth, params["code"])

      true ->
        back(conn, "Die Bank hat keine Freigabe erteilt; es ist nichts verbunden.")
    end
  end

  defp same_state?(%{state: state}, given) when is_binary(given),
    do: Plug.Crypto.secure_compare(state, given)

  defp same_state?(_auth, _given), do: false

  defp connect(conn, auth, code) do
    case BankSync.connect(conn.assigns.current_scope, auth, code) do
      {:ok, connection} -> connected(conn, connection, auth)
      {:error, reason} -> back(conn, "#{refused(auth)}: #{BankSync.error_message(reason)}")
    end
  end

  defp connected(conn, connection, %{connection_id: _id}) do
    conn
    |> put_flash(
      :info,
      "Die Freigabe für #{connection.bank_name} gilt jetzt bis #{Format.date(connection.valid_until)}."
    )
    |> redirect(to: ~p"/budget/bank-connections")
  end

  defp connected(conn, connection, _auth) do
    conn
    |> put_flash(:info, "#{connection.bank_name} ist verbunden. Jetzt die Konten zuordnen.")
    |> redirect(to: ~p"/budget/bank-connections/#{connection}/accounts")
  end

  defp refused(%{connection_id: _id}), do: "Nicht erneuert"
  defp refused(_auth), do: "Nicht verbunden"

  defp back(conn, message),
    do: conn |> put_flash(:error, message) |> redirect(to: ~p"/budget/bank-connections")
end
