defmodule Abakus.Repo.Migrations.CreateScheduledTransactions do
  use Ecto.Migration

  @frequencies ~w(once daily weekly every_other_week twice_a_month every_4_weeks monthly every_other_month
                  every_3_months every_4_months twice_a_year yearly every_other_year)
               |> Enum.map_join(", ", &"'#{&1}'")

  # A day past the end of a month stands for its last day. NULL passes a check, hence coalesce.
  @days """
  CASE WHEN frequency = 'twice_a_month'
    THEN coalesce(first_day BETWEEN 1 AND 30 AND second_day BETWEEN first_day + 1 AND 31, 0)
    ELSE first_day IS NULL AND second_day IS NULL END
  """

  def change do
    create table(:scheduled_transactions, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :user_id, references(:users, on_delete: :restrict), null: false
      add :account_id, references(:accounts, type: :uuid, on_delete: :restrict), null: false
      add :next_date, :date, null: false

      add :frequency, :string,
        null: false,
        check: %{
          name: "scheduled_transactions_frequency_check",
          expr: "frequency IN (#{@frequencies})"
        }

      add :first_day, :integer

      add :second_day, :integer, check: %{name: "scheduled_transactions_days_check", expr: @days}

      add :payee_id, references(:payees, type: :uuid, on_delete: :restrict)
      add :category_id, references(:categories, type: :uuid, on_delete: :restrict)
      add :memo, :string
      add :amount, :integer, null: false

      add :cleared, :string,
        null: false,
        default: "uncleared",
        check: %{
          name: "scheduled_transactions_cleared_check",
          expr: "cleared IN ('uncleared', 'cleared')"
        }

      timestamps(type: :utc_datetime_usec)
    end

    create index(:scheduled_transactions, [:user_id, :next_date])
    create index(:scheduled_transactions, [:account_id])
    create index(:scheduled_transactions, [:payee_id])
    create index(:scheduled_transactions, [:category_id])

    create table(:scheduled_subtransactions, primary_key: false) do
      add :id, :uuid, primary_key: true

      add :scheduled_transaction_id,
          references(:scheduled_transactions, type: :uuid, on_delete: :delete_all),
          null: false

      add :position, :integer, null: false, default: 0
      add :amount, :integer, null: false
      add :payee_id, references(:payees, type: :uuid, on_delete: :restrict)
      add :category_id, references(:categories, type: :uuid, on_delete: :restrict)
      add :memo, :string

      timestamps(type: :utc_datetime_usec)
    end

    create index(:scheduled_subtransactions, [:scheduled_transaction_id, :position])
    create index(:scheduled_subtransactions, [:payee_id])
    create index(:scheduled_subtransactions, [:category_id])

    create table(:payee_rename_conditions, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :user_id, references(:users, on_delete: :restrict), null: false
      add :payee_id, references(:payees, type: :uuid, on_delete: :delete_all), null: false
      add :position, :integer, null: false, default: 0

      add :operator, :string,
        null: false,
        check: %{
          name: "payee_rename_conditions_operator_check",
          expr: "operator IN ('contains', 'is', 'starts_with', 'ends_with')"
        }

      add :text, :string, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:payee_rename_conditions, [:payee_id, :position])
    create index(:payee_rename_conditions, [:user_id])

    alter table(:payees) do
      add :hidden, :boolean, null: false, default: false
    end

    alter table(:transactions) do
      add :scheduled_transaction_id,
          references(:scheduled_transactions, type: :uuid, on_delete: :nilify_all)

      add :scheduled_date, :date
    end

    create index(:transactions, [:scheduled_transaction_id])
  end
end
