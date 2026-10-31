defmodule Abakus.Repo.Migrations.SignInDevices do
  use Ecto.Migration

  def change do
    create table(:devices, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :app, :string, null: false
      add :signed_in_at, :utc_datetime_usec
      add :last_synced_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create index(:devices, [:user_id])

    alter table(:users_tokens) do
      add :device_id, references(:devices, type: :uuid, on_delete: :delete_all)
      add :code_challenge, :string
    end

    create index(:users_tokens, [:device_id])
  end
end
