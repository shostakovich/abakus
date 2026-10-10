defmodule Abakus.ApiTokens do
  @moduledoc """
  Bearer tokens for the YNAB-compatible API: `abk_` and 32 random bytes, stored as SHA-256, so a copy of the database
  grants no access. Revoking deletes the token, which takes effect with the next request.
  """

  import Ecto.Query

  alias Abakus.ApiTokens.ApiToken
  alias Abakus.Repo

  @prefix "abk_"

  def list_api_tokens, do: Repo.all(from t in ApiToken, order_by: [t.inserted_at, t.id])

  def change_api_token(attrs \\ %{}), do: ApiToken.create_changeset(%ApiToken{}, attrs)

  @doc "Creates a token; returns it this once, together with what is stored."
  def create_api_token(attrs) do
    token = @prefix <> Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)

    %ApiToken{token_hash: hash(token)}
    |> ApiToken.create_changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, api_token} -> {:ok, token, api_token}
      error -> error
    end
  end

  @doc "The stored token for `token`, marked as used now in the same query, or `:error`."
  def authenticate(token) when is_binary(token) do
    query = from t in ApiToken, where: t.token_hash == ^hash(token), select: t

    case Repo.update_all(query, set: [last_used_at: DateTime.utc_now()]) do
      {0, _} -> :error
      {1, [api_token]} -> {:ok, api_token}
    end
  end

  @doc "Revokes a token; `id` may come from the client as it is."
  def revoke_api_token(id) do
    with {:ok, id} <- Abakus.Schema.cast_id(id),
         %ApiToken{} = api_token <- Repo.get(ApiToken, id) do
      Repo.delete(api_token)
    else
      _ -> {:error, :not_found}
    end
  end

  defp hash(token), do: :crypto.hash(:sha256, token)
end
