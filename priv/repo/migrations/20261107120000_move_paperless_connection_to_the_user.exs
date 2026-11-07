defmodule Abakus.Repo.Migrations.MovePaperlessConnectionToTheUser do
  use Ecto.Migration

  def up do
    create table(:paperless_connections) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :url, :string, null: false
      add :token, :string, null: false

      timestamps()
    end

    create unique_index(:paperless_connections, [:user_id])

    # A poll counts only from the connection's updated_at on, so the last one before the move still counts.
    execute """
    INSERT INTO paperless_connections (user_id, url, token, inserted_at, updated_at)
    SELECT user_id, paperless_url, paperless_token, inserted_at,
           MIN(COALESCE(paperless_polled_at, updated_at), updated_at)
    FROM depot_settings
    WHERE paperless_url IS NOT NULL AND paperless_token IS NOT NULL
    """

    alter table(:depot_settings) do
      remove :paperless_url
      remove :paperless_token
    end
  end

  def down do
    alter table(:depot_settings) do
      add :paperless_url, :string
      add :paperless_token, :string
    end

    execute """
    UPDATE depot_settings
    SET paperless_url = (SELECT url FROM paperless_connections c WHERE c.user_id = depot_settings.user_id),
        paperless_token = (SELECT token FROM paperless_connections c WHERE c.user_id = depot_settings.user_id)
    """

    drop table(:paperless_connections)
  end
end
