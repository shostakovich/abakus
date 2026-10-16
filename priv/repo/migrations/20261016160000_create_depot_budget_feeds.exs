defmodule Abakus.Repo.Migrations.CreateDepotBudgetFeeds do
  use Ecto.Migration

  def change do
    create table(:depot_budget_feeds) do
      add :account_id, references(:accounts, on_delete: :delete_all), null: false
      add :portfolio_id, references(:depot_portfolios, on_delete: :delete_all)
      add :depot_account_id, references(:depot_accounts, on_delete: :delete_all)

      timestamps()
    end

    create index(:depot_budget_feeds, [:account_id])
    create unique_index(:depot_budget_feeds, [:portfolio_id])
    create unique_index(:depot_budget_feeds, [:depot_account_id])
  end
end
