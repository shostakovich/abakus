defmodule Abakus.Repo.Migrations.CreateKasseBudgetLink do
  use Ecto.Migration

  def change do
    create table(:kasse_budget_links, primary_key: false) do
      add :participant_id, references(:kasse_participants, type: :integer),
        null: false,
        primary_key: true

      add :account_id, references(:accounts, on_delete: :delete_all), null: false

      timestamps()
    end

    create table(:kasse_budget_category_mappings, primary_key: false) do
      add :category_id, references(:kasse_categories, type: :integer),
        null: false,
        primary_key: true

      add :budget_category_id, references(:categories, on_delete: :delete_all), null: false
    end

    create table(:kasse_linked_transactions, primary_key: false, options: "WITHOUT ROWID") do
      add :expense_id, references(:kasse_expenses), null: false, primary_key: true
      add :participant_id, references(:kasse_participants), null: false, primary_key: true
      add :transaction_id, references(:transactions), null: false
      add :written_category_id, references(:categories, on_delete: :nilify_all)
      add :written_memo, :text

      timestamps()
    end

    create unique_index(:kasse_linked_transactions, [:transaction_id])
  end
end
