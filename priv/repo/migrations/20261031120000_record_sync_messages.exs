defmodule Abakus.Repo.Migrations.RecordSyncMessages do
  use Ecto.Migration

  @tombstoned ~w(subtransactions scheduled_transactions scheduled_subtransactions payees payee_rename_conditions
                 category_groups categories assignments target_versions target_snoozes)a

  def change do
    create table(:sync_messages) do
      add :user_id, references(:users, on_delete: :restrict), null: false
      add :table, :string, null: false
      add :row_id, :string, null: false
      add :column, :string, null: false
      add :value, :string, null: false
      add :clock, :string, null: false
      add :device, :string, null: false
      add :inserted_at, :utc_datetime_usec, null: false
    end

    create unique_index(:sync_messages, [:clock, :table, :row_id, :column])
    create index(:sync_messages, [:user_id])

    create table(:sync_field_clocks, primary_key: false) do
      add :table, :string, null: false, primary_key: true
      add :row_id, :string, null: false, primary_key: true
      add :column, :string, null: false, primary_key: true
      add :clock, :string, null: false
    end

    for table <- @tombstoned do
      alter table(table) do
        add :deleted_at, :utc_datetime_usec
      end
    end

    alter table(:categories) do
      add :successor_id, references(:categories, type: :uuid, on_delete: :restrict)
    end

    alter table(:payees) do
      add :successor_id, references(:payees, type: :uuid, on_delete: :restrict)
    end

    drop index(:payees, [:user_id, :lookup_key],
           name: :payees_user_id_lookup_key_index,
           unique: true,
           where: "transfer_account_id IS NULL"
         )

    create index(:payees, [:user_id, :lookup_key])
  end
end
