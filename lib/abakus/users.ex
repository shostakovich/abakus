defmodule Abakus.Users do
  @moduledoc """
  Users sign in with a passkey or, as a fallback, a magic link by email. There are no passwords
  and no sign-up: users are invited by `mix abakus.invite` or `Abakus.Release.invite/1`.
  """

  import Ecto.Query, warn: false

  require Logger

  alias Abakus.RateLimit
  alias Abakus.Repo
  alias Abakus.Users.{Passkey, User, UserNotifier, UserToken}
  alias Abakus.WebAuthn

  @minute 60_000
  # One window per validity of a link, so no more than three links are valid at a time.
  @default_login_link_limits [
    per_email: {3, UserToken.magic_link_validity_in_minutes() * @minute},
    total: {30, 60 * @minute},
    unknown: {30, 60 * @minute}
  ]

  ## Users

  def get_user_by_email(email) when is_binary(email),
    do: Repo.get_by(User, email: User.normalize_email(email))

  def get_user!(id), do: Repo.get!(User, id)

  def create_user(attrs) do
    %User{}
    |> User.create_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Creates a user and mails them a sign-in link at once. `{:error, :mail_not_delivered, user}`
  means the user exists but has to request a link on the sign-in page.
  """
  def invite_user(email, magic_link_url_fun)
      when is_binary(email) and is_function(magic_link_url_fun, 1) do
    with {:ok, user} <- create_user(%{email: email}) do
      case UserNotifier.deliver_invite(user, magic_link_url(user, magic_link_url_fun)) do
        {:ok, _email} -> {:ok, user}
        {:error, _reason} -> {:error, :mail_not_delivered, user}
      end
    end
  end

  @sudo_mode_minutes 10

  def sudo_mode_minutes, do: @sudo_mode_minutes

  @doc """
  Whether the user signed in no more than `minutes` ago (`sudo_mode_minutes/0` by default), as
  required for changes to passkeys and the email address.
  """
  def sudo_mode?(user, minutes \\ @sudo_mode_minutes)

  def sudo_mode?(%User{authenticated_at: ts}, minutes) when is_struct(ts, DateTime) do
    DateTime.after?(ts, DateTime.add(DateTime.utc_now(), -minutes, :minute))
  end

  def sudo_mode?(_user, _minutes), do: false

  ## Email

  def change_user_email(user, attrs \\ %{}, opts \\ []) do
    User.email_changeset(user, attrs, opts)
  end

  @doc "Changes the email to the one the token was sent to, and deletes the token."
  def update_user_email(user, token) do
    context = "change:#{user.email}"

    Repo.transact(fn ->
      with {:ok, query} <- UserToken.verify_change_email_token_query(token, context),
           %UserToken{sent_to: email} <- Repo.one(query),
           {:ok, user} <- Repo.update(User.email_changeset(user, %{email: email})),
           {_count, _result} <-
             Repo.delete_all(from(UserToken, where: [user_id: ^user.id, context: ^context])) do
        {:ok, user}
      else
        _ -> {:error, :transaction_aborted}
      end
    end)
  end

  def deliver_user_update_email_instructions(%User{} = user, current_email, update_email_url_fun)
      when is_function(update_email_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "change:#{current_email}")

    Repo.insert!(user_token)
    UserNotifier.deliver_update_email_instructions(user, update_email_url_fun.(encoded_token))
  end

  ## Session

  def generate_user_session_token(user) do
    {token, user_token} = UserToken.build_session_token(user)
    Repo.insert!(user_token)
    token
  end

  @doc "Returns `{user, token_inserted_at}` for a valid session token, otherwise `nil`."
  def get_user_by_session_token(token) do
    token |> UserToken.verify_session_token_query() |> Repo.one()
  end

  def delete_expired_user_tokens(%User{} = user) do
    Repo.delete_all(UserToken.expired_tokens_query(user.id))
    :ok
  end

  def delete_user_session_token(token) do
    Repo.delete_all(from(UserToken, where: [token: ^token, context: "session"]))
    :ok
  end

  ## Magic link

  def get_user_by_magic_link_token(token) do
    with {:ok, query} <- UserToken.verify_magic_link_token_query(token),
         {user, _token} <- Repo.one(query) do
      user
    else
      _ -> nil
    end
  end

  @doc """
  Signs the user in with a magic link and expires the link; the first link confirms the email.
  Whoever deletes the token first signs in; a request using the same link at the same time gets
  `{:error, :not_found}`.
  """
  def login_user_by_magic_link(token) when is_binary(token) do
    with {:ok, query} <- UserToken.verify_magic_link_token_query(token),
         {user, user_token} <- Repo.one(query) do
      Repo.transact(fn -> use_magic_link(user, user_token) end)
    else
      _ -> {:error, :not_found}
    end
  end

  defp use_magic_link(user, user_token) do
    case Repo.delete_all(from t in UserToken, where: t.id == ^user_token.id) do
      {1, _} when user.confirmed_at != nil -> {:ok, user}
      {1, _} -> Repo.update(User.confirm_changeset(user))
      {0, _} -> {:error, :not_found}
    end
  end

  def deliver_login_instructions(%User{} = user, magic_link_url_fun)
      when is_function(magic_link_url_fun, 1) do
    UserNotifier.deliver_login_instructions(user, magic_link_url(user, magic_link_url_fun))
  end

  defp magic_link_url(user, magic_link_url_fun) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "login")
    Repo.insert!(user_token)
    magic_link_url_fun.(encoded_token)
  end

  @doc "The limits for sign-in links: `{count, window_ms}` per `:per_email`, `:total`, `:unknown`."
  def login_link_limits,
    do: Application.get_env(:abakus, :login_link_limits, @default_login_link_limits)

  @doc """
  Mails a sign-in link if the address belongs to a user, within the limits per address and in
  total. Unknown addresses count in a bucket of their own, so they cannot lock users out; the
  caller gives the same answer in every case.
  """
  def request_login_link(email, magic_link_url_fun)
      when is_binary(email) and is_function(magic_link_url_fun, 1) do
    email = User.normalize_email(email)
    limits = login_link_limits()

    {user, rules} =
      case get_user_by_email(email) do
        %User{} = user ->
          {user,
           [rule({:login_link, email}, limits[:per_email]), rule(:login_links, limits[:total])]}

        nil ->
          {nil, [rule(:unknown_login_links, limits[:unknown])]}
      end

    case RateLimit.hit(rules) do
      :ok when user != nil ->
        deliver_login_instructions(user, magic_link_url_fun)
        :sent

      :ok ->
        :unknown

      {:error, key} ->
        Logger.warning("Login link for #{email_hash(email)} not sent: #{limit_name(key)} reached")
        :rate_limited
    end
  end

  defp rule(key, {limit, window_ms}), do: {key, limit, window_ms}

  # Enough to tell addresses apart in the log without revealing them.
  defp email_hash(email),
    do: :sha256 |> :crypto.hash(email) |> Base.encode16(case: :lower) |> binary_part(0, 12)

  defp limit_name({:login_link, _email}), do: "limit per address"
  defp limit_name(:login_links), do: "limit in total"
  defp limit_name(:unknown_login_links), do: "limit for unknown addresses"

  ## Passkeys

  def list_passkeys(%User{} = user) do
    Repo.all(from p in Passkey, where: p.user_id == ^user.id, order_by: [asc: p.id])
  end

  def passkey_registration_options(%User{} = user, rp, challenge) do
    exclude_ids = Enum.map(list_passkeys(user), & &1.credential_id)

    WebAuthn.registration_options(
      rp,
      challenge,
      %{handle: user.passkey_handle, name: user.email},
      exclude_ids
    )
  end

  @doc """
  Verifies a new passkey from the browser and stores it under `name`. The user gets a mail, as
  a passkey outlives the session that added it.
  """
  def register_passkey(%User{} = user, response, challenge, rp, name) do
    with {:ok, credential} <- WebAuthn.verify_registration(response, challenge, rp),
         {:ok, passkey} <-
           %Passkey{user_id: user.id}
           |> Passkey.create_changeset(Map.put(credential, :name, name))
           |> Repo.insert() do
      UserNotifier.deliver_passkey_added(user, passkey)
      {:ok, passkey}
    end
  end

  @doc "Finds the passkey of an assertion and verifies it; returns its user."
  def authenticate_passkey(response, challenge, rp) do
    with {:ok, credential_id} <- WebAuthn.credential_id(response),
         %Passkey{user: user} = passkey <- passkey_with_user(credential_id),
         {:ok, sign_count} <-
           WebAuthn.verify_authentication(response, challenge, rp, passkey, user.passkey_handle) do
      Repo.update!(Passkey.use_changeset(passkey, sign_count))
      {:ok, user}
    else
      nil -> {:error, :unknown_credential}
      {:error, reason} -> {:error, reason}
    end
  end

  defp passkey_with_user(credential_id) do
    Repo.one(from p in Passkey, where: p.credential_id == ^credential_id, preload: :user)
  end

  @doc "Deletes one of the user's passkeys; `id` may come from the client as it is."
  def delete_passkey(%User{} = user, id) do
    with {:ok, id} <- Abakus.Schema.cast_id(id),
         %Passkey{} = passkey <- Repo.get_by(Passkey, id: id, user_id: user.id) do
      Repo.delete(passkey)
    else
      _ -> {:error, :not_found}
    end
  end
end
