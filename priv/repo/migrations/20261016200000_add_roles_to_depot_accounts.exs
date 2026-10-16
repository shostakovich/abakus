defmodule Abakus.Repo.Migrations.AddRolesToDepotAccounts do
  use Ecto.Migration

  def change do
    alter table(:depot_accounts) do
      add :budget_account_id, references(:accounts, on_delete: :nilify_all)
      add :cash_of_portfolio_id, references(:depot_portfolios, on_delete: :nilify_all)
      add :no_role, :boolean, null: false, default: false
    end

    create unique_index(:depot_accounts, [:budget_account_id])
    create index(:depot_accounts, [:cash_of_portfolio_id])
  end
end
