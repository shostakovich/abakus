defmodule Abakus.Repo.Migrations.DropPortfolioPerformance do
  use Ecto.Migration

  def up do
    execute "UPDATE depot_transactions SET source = 'manual' WHERE source = 'pp_import'"
    execute "UPDATE depot_prices SET source = 'manual' WHERE source = 'pp'"

    # SQLite drops no indexed column.
    drop unique_index(:depot_transactions, [:user_id, :pp_uuid])
    drop unique_index(:depot_accounts, [:user_id, :pp_uuid])
    drop unique_index(:depot_portfolios, [:user_id, :pp_uuid])
    drop unique_index(:depot_taxonomies, [:user_id, :pp_id])
    drop unique_index(:depot_classifications, [:taxonomy_id, :pp_id])
    drop unique_index(:depot_attribute_types, [:pp_id, :target])

    alter table(:depot_transactions) do
      remove :pp_uuid
      remove :pp_other_uuid
      remove :pp_source
    end

    alter table(:depot_accounts) do
      remove :pp_uuid
    end

    alter table(:depot_portfolios) do
      remove :pp_uuid
    end

    alter table(:depot_securities) do
      remove :pp_feed
      remove :pp_ticker
      remove :source
      remove :quote_feed_set_by_user
    end

    alter table(:depot_taxonomies) do
      remove :pp_id
      remove :source
    end

    alter table(:depot_classifications) do
      remove :pp_id
    end

    drop table(:depot_pp_security_links)
    drop table(:depot_savings_plan_transactions)
    drop table(:depot_savings_plans)

    rename table(:depot_attribute_types), :pp_id, to: :key
    create unique_index(:depot_attribute_types, [:key, :target])
  end

  def down, do: raise(Ecto.MigrationError, "dropping the PP import's data is irreversible")
end
