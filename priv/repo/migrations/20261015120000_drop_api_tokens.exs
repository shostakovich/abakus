defmodule Abakus.Repo.Migrations.DropApiTokens do
  use Ecto.Migration

  def up do
    drop table(:api_tokens)
  end

  def down do
    create table(:api_tokens) do
      add :name, :string, null: false
      add :token_hash, :binary, null: false, size: 32
      add :last_used_at, :utc_datetime_usec

      timestamps()
    end

    create unique_index(:api_tokens, [:token_hash])
  end
end
