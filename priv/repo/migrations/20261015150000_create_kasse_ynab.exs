defmodule Abakus.Repo.Migrations.CreateKasseYnab do
  use Ecto.Migration

  def change do
    create table(:kasse_ynab_connections, primary_key: false) do
      add :participant_id, references(:kasse_participants, type: :integer),
        null: false,
        primary_key: true

      add :token, :string
      add :plan_id, :string
      add :account_id, :string
      add :start_date, :date
      add :connected_at, :utc_datetime_usec
      add :last_run_at, :utc_datetime_usec
      add :last_synced_at, :utc_datetime_usec
      add :summary, :string
      add :error, :string

      add :token_invalid, :boolean,
        null: false,
        default: false,
        check: %{
          name: "kasse_ynab_connections_token_invalid_check",
          expr: "token_invalid IN (0, 1)"
        }

      add :retry_at, :utc_datetime_usec
      add :backoff_seconds, :integer, null: false, default: 0

      timestamps()
    end

    create table(:kasse_ynab_category_mappings, primary_key: false, options: "WITHOUT ROWID") do
      add :participant_id, references(:kasse_participants), null: false, primary_key: true
      add :category_id, references(:kasse_categories), null: false, primary_key: true
      add :ynab_category_id, :string, null: false
    end

    create table(:kasse_ynab_transactions, primary_key: false, options: "WITHOUT ROWID") do
      add :expense_id, references(:kasse_expenses), null: false, primary_key: true
      add :participant_id, references(:kasse_participants), null: false, primary_key: true
      add :ynab_transaction_id, :string

      add :state, :string,
        null: false,
        default: "unknown",
        check: %{
          name: "kasse_ynab_transactions_state_check",
          expr: "state IN ('unknown', 'synced', 'pending', 'retarget', 'failed', 'delete_failed')"
        }

      add :fingerprint, :string
      add :synced_at, :utc_datetime_usec
      add :last_error, :string
    end

    create index(:kasse_ynab_transactions, [:participant_id])
  end
end
