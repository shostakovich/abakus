defmodule Abakus.ApiTokens.ApiToken do
  @moduledoc "A bearer token for the API, stored as its SHA-256; the token itself is shown once, when created."

  use Abakus.Schema

  import Ecto.Changeset

  schema "api_tokens" do
    field :name, :string
    field :token_hash, :binary, redact: true
    field :last_used_at, :utc_datetime_usec

    timestamps()
  end

  def create_changeset(api_token, attrs) do
    api_token
    |> cast(attrs, [:name])
    |> update_change(:name, &String.trim/1)
    |> validate_required([:name])
    |> validate_length(:name, max: 60)
  end
end
