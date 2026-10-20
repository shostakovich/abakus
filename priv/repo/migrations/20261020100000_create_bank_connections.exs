defmodule Abakus.Repo.Migrations.CreateBankConnections do
  use Ecto.Migration

  def change do
    create table(:bank_connections) do
      add :user_id, references(:users, on_delete: :restrict), null: false
      add :provider, :string, null: false
      add :bank_name, :string, null: false
      add :bank_country, :string, null: false
      add :session_id, :string, null: false
      add :valid_until, :utc_datetime_usec, null: false
      add :reminders_sent, {:array, :integer}, null: false, default: []
      add :last_sync_at, :utc_datetime_usec
      add :last_error, :string

      timestamps()
    end

    create index(:bank_connections, [:user_id])
    create unique_index(:bank_connections, [:provider, :session_id])

    create table(:bank_linked_accounts) do
      add :connection_id, references(:bank_connections, on_delete: :delete_all), null: false
      add :provider_account_id, :string, null: false
      add :name, :string
      add :iban, :string
      add :account_id, references(:accounts, on_delete: :restrict)
      add :start_date, :date

      timestamps()
    end

    create unique_index(:bank_linked_accounts, [:connection_id, :provider_account_id])
    create unique_index(:bank_linked_accounts, [:account_id])

    create table(:bank_sync_runs) do
      add :connection_id, references(:bank_connections, on_delete: :delete_all), null: false
      add :started_at, :utc_datetime_usec, null: false
      add :trigger, :string, null: false
      add :new, :integer, null: false, default: 0
      add :matched, :integer, null: false, default: 0
      add :error, :string

      timestamps()
    end

    create index(:bank_sync_runs, [:connection_id, :started_at])
  end
end
