defmodule Abakus.Repo.Migrations.CreateDepotBudgetLinks do
  use Ecto.Migration

  def change do
    create table(:depot_budget_links, primary_key: false) do
      add :user_id, references(:users, on_delete: :delete_all), null: false, primary_key: true
      add :category_id, references(:categories), null: false
      add :start_date, :date, null: false

      timestamps()
    end

    create table(:depot_linked_transactions) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :depot_transaction_id, references(:depot_transactions, on_delete: :nilify_all)
      add :transaction_id, references(:transactions), null: false
      add :written_account_id, references(:accounts), null: false
      add :written_amount, :integer, null: false
      add :written_date, :date, null: false
      add :written_payee_id, references(:payees, on_delete: :nilify_all)

      timestamps()
    end

    create unique_index(:depot_linked_transactions, [:depot_transaction_id])
    create unique_index(:depot_linked_transactions, [:transaction_id])
    create index(:depot_linked_transactions, [:user_id])
  end
end
