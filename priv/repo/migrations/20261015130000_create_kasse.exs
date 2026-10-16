defmodule Abakus.Repo.Migrations.CreateKasse do
  use Ecto.Migration

  def change do
    create table(:kasse_participants) do
      add :user_id, references(:users), null: false

      add :name, :string,
        null: false,
        collate: :nocase,
        check: %{name: "kasse_participants_name_check", expr: "length(trim(name)) > 0"}

      add :archived_at, :utc_datetime_usec

      timestamps()
    end

    create unique_index(:kasse_participants, [:name])
    create unique_index(:kasse_participants, [:user_id])

    create table(:kasse_categories) do
      add :name, :string,
        null: false,
        collate: :nocase,
        check: %{name: "kasse_categories_name_check", expr: "length(trim(name)) > 0"}

      add :position, :integer, null: false, default: 0
      add :archived_at, :utc_datetime_usec

      timestamps()
    end

    create unique_index(:kasse_categories, [:name])

    create table(:kasse_settings, primary_key: false) do
      add :id, :integer,
        primary_key: true,
        check: %{name: "kasse_settings_id_check", expr: "id = 1"}

      add :group_name, :string, null: false

      timestamps()
    end

    create table(:kasse_recurring_expenses) do
      add :template, :map, null: false

      add :frequency, :string,
        null: false,
        check: %{
          name: "kasse_recurring_expenses_frequency_check",
          expr: "frequency IN ('weekly', 'monthly', 'yearly')"
        }

      add :start_date, :date, null: false
      add :next_date, :date, null: false

      add :active, :boolean,
        null: false,
        default: true,
        check: %{name: "kasse_recurring_expenses_active_check", expr: "active IN (0, 1)"}

      add :created_by_id, references(:kasse_participants)

      timestamps()
    end

    create index(:kasse_recurring_expenses, [:next_date], where: "active = 1")

    create table(:kasse_expenses) do
      add :title, :string, null: false
      add :title_folded, :string, null: false
      add :date, :date, null: false
      add :category_id, references(:kasse_categories)
      add :paid_by_id, references(:kasse_participants), null: false
      add :notes, :string, null: false, default: ""
      add :notes_folded, :string, null: false, default: ""

      add :reimbursement, :boolean,
        null: false,
        default: false,
        check: %{name: "kasse_expenses_reimbursement_check", expr: "reimbursement IN (0, 1)"}

      add :split_mode, :string,
        null: false,
        check: %{
          name: "kasse_expenses_split_mode_check",
          expr: "split_mode IN ('equal', 'shares', 'percent', 'amount')"
        }

      add :amount_cents, :integer,
        null: false,
        check: %{name: "kasse_expenses_amount_cents_check", expr: "amount_cents > 0"}

      add :original_amount, :integer, null: false
      add :original_currency, :string, null: false, default: "EUR"
      add :fx_rate, :real, null: false, default: 1.0

      add :fx_source, :string,
        check: %{name: "kasse_expenses_fx_source_check", expr: "fx_source IN ('ecb', 'manual')"}

      add :recurring_expense_id,
          references(:kasse_recurring_expenses, on_delete: :nilify_all)

      add :deleted_at, :utc_datetime_usec

      timestamps()
    end

    create index(:kasse_expenses, ["date DESC", "id DESC"],
             name: :kasse_expenses_date_index,
             where: "deleted_at IS NULL"
           )

    create index(:kasse_expenses, [:paid_by_id])
    create index(:kasse_expenses, [:category_id])

    create unique_index(:kasse_expenses, [:recurring_expense_id, :date],
             where: "recurring_expense_id IS NOT NULL"
           )

    create table(:kasse_expense_shares, primary_key: false, options: "WITHOUT ROWID") do
      add :expense_id, references(:kasse_expenses, on_delete: :delete_all),
        null: false,
        primary_key: true

      add :participant_id, references(:kasse_participants), null: false, primary_key: true
      add :weight, :integer, null: false
      add :amount_cents, :integer, null: false
    end

    create index(:kasse_expense_shares, [:participant_id])

    create table(:kasse_activities) do
      add :actor_id, references(:kasse_participants)

      add :action, :string,
        null: false,
        check: %{
          name: "kasse_activities_action_check",
          expr:
            "action IN ('expense_created', 'expense_updated', 'expense_deleted', " <>
              "'settings_updated', 'recurring_created', 'recurring_deleted')"
        }

      add :expense_id, references(:kasse_expenses)
      add :details, :map, null: false, default: %{}

      timestamps(updated_at: false)
    end

    create index(:kasse_activities, [:expense_id])

    create table(:kasse_fx_rates, primary_key: false, options: "WITHOUT ROWID") do
      add :currency, :string, null: false, primary_key: true

      add :source, :string,
        null: false,
        primary_key: true,
        check: %{name: "kasse_fx_rates_source_check", expr: "source IN ('ecb', 'manual')"}

      add :date, :date, null: false, primary_key: true

      add :rate, :real,
        null: false,
        check: %{name: "kasse_fx_rates_rate_check", expr: "rate > 0"}
    end
  end
end
