defmodule Abakus.Users.UserToken do
  @moduledoc """
  Session tokens are stored as they are, since they only live in the signed session and cookie.
  Tokens sent by mail are stored hashed, so a read-only copy of the database signs no one in;
  they also stop working once the user's email changes. So are the tokens of a signed-in app (`Abakus.Devices`),
  which belong to its device: an authorization code with its PKCE challenge, access and refresh tokens, and the
  refresh tokens rotated away, kept to notice their reuse.
  """
  use Abakus.Schema
  import Ecto.Query
  alias Abakus.Users.UserToken

  @hash_algorithm :sha256
  @rand_size 32

  # Short, since anyone with access to the mailbox may sign in.
  @magic_link_validity_in_minutes 15
  @change_email_validity_in_days 7
  @session_validity_in_days 14
  @app_code_validity_in_seconds 60
  @app_access_validity_in_seconds 60 * 60
  @app_refresh_validity_in_days 90
  @app_contexts ~w(app_code app_access app_refresh app_refresh_used)

  schema "users_tokens" do
    field :token, :binary
    field :context, :string
    field :sent_to, :string
    field :authenticated_at, :utc_datetime_usec
    field :code_challenge, :string
    belongs_to :user, Abakus.Users.User
    belongs_to :device, Abakus.Devices.Device, type: Ecto.UUID

    timestamps(updated_at: false)
  end

  def magic_link_validity_in_minutes, do: @magic_link_validity_in_minutes
  def app_access_validity_in_seconds, do: @app_access_validity_in_seconds
  def app_refresh_validity_in_days, do: @app_refresh_validity_in_days

  def build_session_token(user) do
    token = :crypto.strong_rand_bytes(@rand_size)
    dt = user.authenticated_at || DateTime.utc_now()
    {token, %UserToken{token: token, context: "session", user_id: user.id, authenticated_at: dt}}
  end

  @doc "A query for `{user, token_inserted_at}` of a session token younger than 14 days."
  def verify_session_token_query(token) do
    from token in by_token_and_context_query(token, "session"),
      join: user in assoc(token, :user),
      where: token.inserted_at > ago(@session_validity_in_days, "day"),
      select: {%{user | authenticated_at: token.authenticated_at}, token.inserted_at}
  end

  @doc "Returns the encoded token for the mail and the hashed one to store."
  def build_email_token(user, context) do
    token = :crypto.strong_rand_bytes(@rand_size)

    {Base.url_encode64(token, padding: false),
     %UserToken{
       token: :crypto.hash(@hash_algorithm, token),
       context: context,
       sent_to: user.email,
       user_id: user.id
     }}
  end

  @doc "A query for `{user, token}` of a magic link still valid for the user's current email."
  def verify_magic_link_token_query(token) do
    with {:ok, query} <- hashed_token_query(token, "login") do
      {:ok,
       from(token in query,
         join: user in assoc(token, :user),
         where: token.inserted_at > ago(^@magic_link_validity_in_minutes, "minute"),
         where: token.sent_to == user.email,
         select: {user, token}
       )}
    end
  end

  @doc "A query for the token of an email change; `context` is `\"change:\" <> old_email`."
  def verify_change_email_token_query(token, "change:" <> _ = context) do
    with {:ok, query} <- hashed_token_query(token, context) do
      {:ok, where(query, [token], token.inserted_at > ago(@change_email_validity_in_days, "day"))}
    end
  end

  @doc """
  Returns the encoded token for the app and the hashed one to store, for the device's `context`: `"app_code"`
  (with the PKCE challenge), `"app_access"` or `"app_refresh"`.
  """
  def build_app_token(device, context, code_challenge \\ nil)
      when context in ~w(app_code app_access app_refresh) do
    token = :crypto.strong_rand_bytes(@rand_size)

    {Base.url_encode64(token, padding: false),
     %UserToken{
       token: :crypto.hash(@hash_algorithm, token),
       context: context,
       user_id: device.user_id,
       device_id: device.id,
       code_challenge: code_challenge
     }}
  end

  @doc "A query for an app's token of one of the `contexts` that is still valid."
  def verify_app_token_query(token, contexts) do
    with {:ok, decoded} <- Base.url_decode64(token, padding: false) do
      hashed = :crypto.hash(@hash_algorithm, decoded)
      {:ok, from(t in UserToken, where: t.token == ^hashed and t.context in ^contexts) |> valid()}
    end
  end

  defp valid(query), do: where(query, ^app_valid())

  defp app_valid do
    dynamic(
      [t],
      (t.context == "app_code" and t.inserted_at > ago(^@app_code_validity_in_seconds, "second")) or
        (t.context == "app_access" and
           t.inserted_at > ago(^@app_access_validity_in_seconds, "second")) or
        (t.context in ["app_refresh", "app_refresh_used"] and
           t.inserted_at > ago(@app_refresh_validity_in_days, "day"))
    )
  end

  @doc "A query for the user's tokens that have expired."
  def expired_tokens_query(user_id) do
    from t in UserToken,
      where: t.user_id == ^user_id,
      where: ^dynamic([t], ^expired_by_email_or_session() or ^expired_app_token())
  end

  defp expired_by_email_or_session do
    dynamic(
      [t],
      (t.context == "session" and t.inserted_at <= ago(@session_validity_in_days, "day")) or
        (t.context == "login" and
           t.inserted_at <= ago(^@magic_link_validity_in_minutes, "minute")) or
        (like(t.context, "change:%") and
           t.inserted_at <= ago(@change_email_validity_in_days, "day"))
    )
  end

  defp expired_app_token,
    do: dynamic([t], t.context in @app_contexts and not (^app_valid()))

  defp hashed_token_query(token, context) do
    with {:ok, decoded} <- Base.url_decode64(token, padding: false) do
      {:ok, by_token_and_context_query(:crypto.hash(@hash_algorithm, decoded), context)}
    end
  end

  defp by_token_and_context_query(token, context) do
    from UserToken, where: [token: ^token, context: ^context]
  end
end
