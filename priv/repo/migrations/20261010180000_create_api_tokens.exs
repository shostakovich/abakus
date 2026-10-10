defmodule Abakus.Repo.Migrations.CreateApiTokens do
  use Ecto.Migration

  def change do
    create table(:api_tokens) do
      add :name, :string, null: false
      add :token_hash, :binary, null: false, size: 32
      add :last_used_at, :utc_datetime_usec

      timestamps()
    end

    create unique_index(:api_tokens, [:token_hash])
  end
end
