defmodule Abakus.Users.UserToken do
  @moduledoc """
  Session tokens are stored as they are, since they only live in the signed session and cookie.
  Tokens sent by mail are stored hashed, so a read-only copy of the database signs no one in;
  they also stop working once the user's email changes.
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

  schema "users_tokens" do
    field :token, :binary
    field :context, :string
    field :sent_to, :string
    field :authenticated_at, :utc_datetime_usec
    belongs_to :user, Abakus.Users.User

    timestamps(updated_at: false)
  end

  def magic_link_validity_in_minutes, do: @magic_link_validity_in_minutes

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

  @doc "A query for the user's tokens that have expired."
  def expired_tokens_query(user_id) do
    from t in UserToken,
      where: t.user_id == ^user_id,
      where:
        (t.context == "session" and t.inserted_at <= ago(@session_validity_in_days, "day")) or
          (t.context == "login" and
             t.inserted_at <= ago(^@magic_link_validity_in_minutes, "minute")) or
          (like(t.context, "change:%") and
             t.inserted_at <= ago(@change_email_validity_in_days, "day"))
  end

  defp hashed_token_query(token, context) do
    with {:ok, decoded} <- Base.url_decode64(token, padding: false) do
      {:ok, by_token_and_context_query(:crypto.hash(@hash_algorithm, decoded), context)}
    end
  end

  defp by_token_and_context_query(token, context) do
    from UserToken, where: [token: ^token, context: ^context]
  end
end
