defmodule Abakus.ApiTokensTest do
  use Abakus.DataCase

  alias Abakus.ApiTokens
  alias Abakus.ApiTokens.ApiToken

  test "creates a token with the prefix, stores only its SHA-256 and finds it by the token" do
    {:ok, "abk_" <> _ = token, %ApiToken{} = api_token} =
      ApiTokens.create_api_token(%{name: " Zipfelkasse "})

    assert api_token.name == "Zipfelkasse"
    stored = Repo.get!(ApiToken, api_token.id)
    assert stored.token_hash == :crypto.hash(:sha256, token)

    columns = stored |> Map.from_struct() |> Map.values()
    refute token in columns

    assert {:ok, %ApiToken{id: id, last_used_at: %DateTime{}}} = ApiTokens.authenticate(token)
    assert id == api_token.id
    assert Repo.get!(ApiToken, id).last_used_at
  end

  test "marks the token as used on every authentication" do
    {:ok, token, _api_token} = ApiTokens.create_api_token(%{name: "Zipfelkasse"})

    {:ok, %ApiToken{last_used_at: first}} = ApiTokens.authenticate(token)
    {:ok, %ApiToken{id: id, last_used_at: second}} = ApiTokens.authenticate(token)

    assert DateTime.after?(second, first)
    assert Repo.get!(ApiToken, id).last_used_at == second
  end

  test "every token is new" do
    {:ok, first, _} = ApiTokens.create_api_token(%{name: "A"})
    {:ok, second, _} = ApiTokens.create_api_token(%{name: "A"})

    assert first != second
    assert byte_size(first) > 40
  end

  test "refuses unknown, malformed and revoked tokens" do
    {:ok, token, api_token} = ApiTokens.create_api_token(%{name: "Zipfelkasse"})

    assert ApiTokens.authenticate("abk_unknown") == :error
    assert ApiTokens.authenticate("") == :error
    assert ApiTokens.authenticate(token <> "x") == :error

    assert {:ok, _} = ApiTokens.revoke_api_token(api_token.id)
    assert ApiTokens.authenticate(token) == :error
    assert ApiTokens.revoke_api_token(api_token.id) == {:error, :not_found}
    assert ApiTokens.revoke_api_token("x") == {:error, :not_found}
    assert ApiTokens.revoke_api_token("99999999999999999999") == {:error, :not_found}
  end

  test "asks for a name of at most 60 characters" do
    assert {:error, changeset} = ApiTokens.create_api_token(%{name: "  "})
    assert "can't be blank" in errors_on(changeset).name

    assert {:error, changeset} = ApiTokens.create_api_token(%{name: String.duplicate("x", 61)})
    assert errors_on(changeset).name != []
  end

  test "lists the tokens oldest first" do
    {:ok, _, first} = ApiTokens.create_api_token(%{name: "Erstes"})
    {:ok, _, second} = ApiTokens.create_api_token(%{name: "Zweites"})

    assert Enum.map(ApiTokens.list_api_tokens(), & &1.id) == [first.id, second.id]
  end
end
