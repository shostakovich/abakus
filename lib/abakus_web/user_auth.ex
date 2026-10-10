defmodule AbakusWeb.UserAuth do
  @moduledoc """
  Session handling for signed-in users. A sign-in always sets the remember-me cookie, so a
  device stays signed in until the session token expires.
  """
  use AbakusWeb, :verified_routes

  import Plug.Conn
  import Phoenix.Controller

  alias Abakus.Users
  alias Abakus.Users.Scope

  # Matches the session validity in UserToken.
  @max_cookie_age_in_days 14
  @remember_me_cookie "_abakus_web_user_remember_me"
  # Behind https, ForwardedSSL marks every cookie `secure`.
  @remember_me_options [
    sign: true,
    max_age: @max_cookie_age_in_days * 24 * 60 * 60,
    same_site: "Lax",
    http_only: true
  ]

  # An active user gets a fresh session token once the current one is this old.
  @session_reissue_age_in_days 7

  @doc "The link in sign-in mails, for a token from `Abakus.Users`."
  def magic_link_url(token), do: url(~p"/users/log-in/#{token}")

  @doc """
  Signs the user in and redirects to the page they wanted, or to the budget. When another user
  signs in over the session, the session token it replaces stops working and its sockets are
  disconnected; the same user signing in again (sudo mode) keeps it, so open tabs keep working.
  The user's expired tokens are cleaned up on the way.
  """
  def log_in_user(conn, user) do
    user_return_to = get_session(conn, :user_return_to)
    replaced_token = get_session(conn, :user_token)
    same_user? = same_user?(conn, user)
    Users.delete_expired_user_tokens(user)

    conn =
      conn
      |> create_or_extend_session(user)
      |> delete_session(:user_return_to)
      |> redirect(to: user_return_to || ~p"/")

    if is_binary(replaced_token) and not same_user? do
      Users.delete_user_session_token(replaced_token)
      AbakusWeb.Endpoint.broadcast(user_session_topic(replaced_token), "disconnect", %{})
    end

    conn
  end

  def log_out_user(conn) do
    user_token = get_session(conn, :user_token)
    user_token && Users.delete_user_session_token(user_token)

    if live_socket_id = get_session(conn, :live_socket_id) do
      AbakusWeb.Endpoint.broadcast(live_socket_id, "disconnect", %{})
    end

    conn
    |> renew_session(nil)
    |> delete_resp_cookie(@remember_me_cookie, @remember_me_options)
    |> redirect(to: ~p"/users/log-in")
  end

  @doc """
  Assigns the scope from the session or, if its token is missing or dead, the remember-me
  cookie; reissues old tokens.
  """
  def fetch_current_scope_for_user(conn, _opts) do
    case user_from_session(conn) || user_from_cookie(conn) do
      {conn, user, token_inserted_at} ->
        conn
        |> assign(:current_scope, Scope.for_user(user))
        |> maybe_reissue_user_session_token(user, token_inserted_at)

      nil ->
        conn |> drop_dead_token() |> assign(:current_scope, Scope.for_user(nil))
    end
  end

  defp user_from_session(conn) do
    with token when is_binary(token) <- get_session(conn, :user_token),
         {user, token_inserted_at} <- Users.get_user_by_session_token(token) do
      {conn, user, token_inserted_at}
    end
  end

  defp user_from_cookie(conn) do
    conn = fetch_cookies(conn, signed: [@remember_me_cookie])

    with token when is_binary(token) <- conn.cookies[@remember_me_cookie],
         {user, token_inserted_at} <- Users.get_user_by_session_token(token) do
      {put_token_in_session(conn, token), user, token_inserted_at}
    end
  end

  defp drop_dead_token(conn) do
    if get_session(conn, :user_token) do
      conn |> delete_session(:user_token) |> delete_session(:live_socket_id)
    else
      conn
    end
  end

  defp maybe_reissue_user_session_token(conn, user, token_inserted_at) do
    token_age = DateTime.diff(DateTime.utc_now(), token_inserted_at, :day)

    if token_age >= @session_reissue_age_in_days do
      create_or_extend_session(conn, user)
    else
      conn
    end
  end

  # A new session clears the old one (session fixation); an extended one keeps it. A reissued
  # token leaves the old one valid until it expires, as requests with the old cookie may still
  # be on their way.
  defp create_or_extend_session(conn, user) do
    token = Users.generate_user_session_token(user)

    conn
    |> renew_session(user)
    |> put_token_in_session(token)
    |> put_resp_cookie(@remember_me_cookie, token, @remember_me_options)
  end

  # The same user signing in again keeps the session and its CSRF token, which the sockets of
  # open tabs are checked against.
  defp renew_session(conn, user) do
    if same_user?(conn, user) do
      conn
    else
      delete_csrf_token()

      conn
      |> configure_session(renew: true)
      |> clear_session()
    end
  end

  defp same_user?(conn, %{id: id}),
    do: match?(%Scope{user: %{id: ^id}}, conn.assigns[:current_scope])

  defp same_user?(_conn, nil), do: false

  defp put_token_in_session(conn, token) do
    conn
    |> put_session(:user_token, token)
    |> put_session(:live_socket_id, user_session_topic(token))
  end

  defp user_session_topic(token), do: "users_sessions:#{Base.url_encode64(token)}"

  @doc """
  `on_mount` for LiveViews: `:mount_current_scope` assigns the scope (or `nil`),
  `:require_authenticated` also redirects anonymous visitors to the sign-in page.
  """
  def on_mount(:mount_current_scope, _params, session, socket) do
    {:cont, mount_current_scope(socket, session)}
  end

  def on_mount(:require_authenticated, _params, session, socket) do
    socket = mount_current_scope(socket, session)

    if socket.assigns.current_scope && socket.assigns.current_scope.user do
      {:cont, socket}
    else
      halt_to_login(socket, "Bitte melde dich an.")
    end
  end

  def on_mount(:require_sudo_mode, _params, session, socket) do
    socket = mount_current_scope(socket, session)

    if Users.sudo_mode?(socket.assigns.current_scope.user) do
      {:cont, socket}
    else
      # Through the page's plug, which sends the user to sign in and back.
      {:halt, Phoenix.LiveView.redirect(socket, to: ~p"/settings/access")}
    end
  end

  defp halt_to_login(socket, message) do
    {:halt,
     socket
     |> Phoenix.LiveView.put_flash(:error, message)
     |> Phoenix.LiveView.redirect(to: ~p"/users/log-in")}
  end

  defp mount_current_scope(socket, session) do
    Phoenix.Component.assign_new(socket, :current_scope, fn ->
      with token when is_binary(token) <- session["user_token"],
           {user, _token_inserted_at} <- Users.get_user_by_session_token(token) do
        Scope.for_user(user)
      end
    end)
  end

  @doc """
  Plug for routes that require a signed-in user. JSON requests (the passkey hooks) get a 401, so
  the page can reload into the sign-in page.
  """
  def require_authenticated_user(conn, _opts) do
    cond do
      conn.assigns.current_scope && conn.assigns.current_scope.user ->
        conn

      conn.private[:phoenix_format] == "json" ->
        conn |> put_status(:unauthorized) |> json(%{error: "session"}) |> halt()

      true ->
        conn
        |> put_flash(:error, "Bitte melde dich an.")
        |> maybe_store_return_to()
        |> redirect(to: ~p"/users/log-in")
        |> halt()
    end
  end

  @doc """
  Plug for pages that change the sign-in (passkeys, email). Sends the user to sign in again and
  back to the page, so a confirmation link opened later still works.
  """
  def require_sudo_mode(conn, _opts) do
    if Users.sudo_mode?(conn.assigns.current_scope.user) do
      conn
    else
      conn
      |> put_flash(:error, "Bitte melde dich für diese Änderung erneut an.")
      |> maybe_store_return_to()
      |> redirect(to: ~p"/users/log-in")
      |> halt()
    end
  end

  defp maybe_store_return_to(%{method: "GET"} = conn) do
    put_session(conn, :user_return_to, current_path(conn))
  end

  defp maybe_store_return_to(conn), do: conn
end
