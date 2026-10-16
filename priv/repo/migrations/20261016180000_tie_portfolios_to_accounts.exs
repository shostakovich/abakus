defmodule Abakus.Repo.Migrations.TiePortfoliosToAccounts do
  use Ecto.Migration

  def up do
    alter table(:depot_portfolios) do
      add :budget_account_id, references(:accounts, on_delete: :nilify_all)
    end

    create unique_index(:depot_portfolios, [:budget_account_id])

    drop table(:depot_budget_feeds)
  end

  def down do
    create table(:depot_budget_feeds) do
      add :account_id, references(:accounts, on_delete: :delete_all), null: false
      add :portfolio_id, references(:depot_portfolios, on_delete: :delete_all)
      add :depot_account_id, references(:depot_accounts, on_delete: :delete_all)

      timestamps()
    end

    create index(:depot_budget_feeds, [:account_id])
    create unique_index(:depot_budget_feeds, [:portfolio_id])
    create unique_index(:depot_budget_feeds, [:depot_account_id])

    drop index(:depot_portfolios, [:budget_account_id])

    alter table(:depot_portfolios) do
      remove :budget_account_id
    end
  end
end
