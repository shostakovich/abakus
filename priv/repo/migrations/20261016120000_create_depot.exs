defmodule Abakus.Repo.Migrations.CreateDepot do
  use Ecto.Migration

  def change do
    create table(:depot_attribute_types) do
      add :pp_id, :string, null: false
      add :name, :string, null: false
      add :column_label, :string
      add :target, :string
      add :value_type, :string
      add :converter, :string

      timestamps()
    end

    create unique_index(:depot_attribute_types, [:pp_id, :target])

    create table(:depot_securities) do
      add :name, :string, null: false
      add :isin, :string
      add :wkn, :string
      add :currency, :string
      add :note, :text
      add :retired, :boolean, null: false, default: false
      add :attributes, :map, null: false, default: %{}
      add :pp_feed, :string
      add :pp_ticker, :string
      add :quote_feed, :string, null: false, default: "manual"
      add :symbol, :string
      add :quote_feed_set_by_user, :boolean, null: false, default: false
      add :latest_date, :date
      add :latest_close, :integer
      add :latest_at, :utc_datetime_usec
      add :fetched_at, :utc_datetime_usec
      add :checked_at, :utc_datetime_usec
      add :fetch_error, :string
      add :source, :string, null: false, default: "pp_import"

      timestamps()
    end

    # Not unique: a PP file may hold the same ISIN twice (other exchange or currency).
    create index(:depot_securities, [:isin])

    create table(:depot_pp_security_links) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :security_id, references(:depot_securities, on_delete: :delete_all), null: false
      add :pp_uuid, :string, null: false

      timestamps()
    end

    create unique_index(:depot_pp_security_links, [:user_id, :pp_uuid])
    create index(:depot_pp_security_links, [:security_id])

    create table(:depot_prices) do
      add :security_id, references(:depot_securities, on_delete: :delete_all), null: false
      add :date, :date, null: false
      add :close, :integer, null: false
      add :source, :string, null: false
    end

    create unique_index(:depot_prices, [:security_id, :date])

    create table(:depot_accounts) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :currency, :string, null: false
      add :note, :text
      add :retired, :boolean, null: false, default: false
      add :attributes, :map, null: false, default: %{}
      add :pp_uuid, :string

      timestamps()
    end

    create unique_index(:depot_accounts, [:user_id, :pp_uuid])

    create table(:depot_portfolios) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :reference_account_id, references(:depot_accounts, on_delete: :nilify_all)
      add :name, :string, null: false
      add :note, :text
      add :retired, :boolean, null: false, default: false
      add :attributes, :map, null: false, default: %{}
      add :pp_uuid, :string
      add :depot_number, :string

      timestamps()
    end

    create unique_index(:depot_portfolios, [:user_id, :pp_uuid])

    create table(:depot_transactions) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :type, :string, null: false
      add :date_time, :naive_datetime, null: false
      add :portfolio_id, references(:depot_portfolios, on_delete: :delete_all)
      add :account_id, references(:depot_accounts, on_delete: :delete_all)
      add :other_portfolio_id, references(:depot_portfolios, on_delete: :delete_all)
      add :other_account_id, references(:depot_accounts, on_delete: :delete_all)
      add :security_id, references(:depot_securities, on_delete: :restrict)
      add :shares, :integer
      add :amount, :integer, null: false
      add :currency, :string, null: false
      add :ex_date, :naive_datetime
      add :note, :text
      add :source, :string, null: false
      add :pp_uuid, :string
      add :pp_other_uuid, :string
      add :pp_source, :string

      timestamps()
    end

    create unique_index(:depot_transactions, [:user_id, :pp_uuid])
    create index(:depot_transactions, [:portfolio_id])
    create index(:depot_transactions, [:account_id])
    create index(:depot_transactions, [:security_id])

    create table(:depot_transaction_units) do
      add :transaction_id, references(:depot_transactions, on_delete: :delete_all), null: false
      add :type, :string, null: false
      add :amount, :integer, null: false
      add :currency, :string, null: false
      add :fx_amount, :integer
      add :fx_currency, :string
      add :fx_rate, :decimal
    end

    create index(:depot_transaction_units, [:transaction_id])

    create table(:depot_savings_plans) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :note, :text
      add :type, :string, null: false
      add :security_id, references(:depot_securities, on_delete: :restrict)
      add :portfolio_id, references(:depot_portfolios, on_delete: :delete_all)
      add :account_id, references(:depot_accounts, on_delete: :delete_all)
      add :auto_generate, :boolean, null: false, default: false
      add :start, :date, null: false
      add :interval, :integer, null: false
      add :amount, :integer, null: false
      add :fees, :integer, null: false, default: 0
      add :taxes, :integer, null: false, default: 0
      add :attributes, :map, null: false, default: %{}

      timestamps()
    end

    create index(:depot_savings_plans, [:user_id])

    create table(:depot_savings_plan_transactions, primary_key: false) do
      add :savings_plan_id, references(:depot_savings_plans, on_delete: :delete_all), null: false
      add :transaction_id, references(:depot_transactions, on_delete: :delete_all), null: false
    end

    create unique_index(:depot_savings_plan_transactions, [:savings_plan_id, :transaction_id])

    create table(:depot_taxonomies) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :source, :string
      add :dimensions, {:array, :string}, null: false, default: []
      add :pp_id, :string

      timestamps()
    end

    create unique_index(:depot_taxonomies, [:user_id, :pp_id])

    create table(:depot_classifications) do
      add :taxonomy_id, references(:depot_taxonomies, on_delete: :delete_all), null: false
      add :parent_id, references(:depot_classifications, on_delete: :delete_all)
      add :name, :string, null: false
      add :note, :text
      add :color, :string
      add :weight, :integer, null: false
      add :rank, :integer, null: false, default: 0
      add :pp_id, :string

      timestamps()
    end

    create unique_index(:depot_classifications, [:taxonomy_id, :pp_id])
    create index(:depot_classifications, [:parent_id])

    create table(:depot_assignments) do
      add :classification_id, references(:depot_classifications, on_delete: :delete_all),
        null: false

      add :security_id, references(:depot_securities, on_delete: :delete_all)

      add :account_id, references(:depot_accounts, on_delete: :delete_all),
        check: %{
          name: "depot_assignments_security_or_account",
          expr: "(security_id IS NULL) <> (account_id IS NULL)"
        }

      add :weight, :integer, null: false
      add :rank, :integer, null: false, default: 0
    end

    create index(:depot_assignments, [:classification_id])

    create table(:depot_exchange_rates) do
      add :currency, :string, null: false
      add :date, :date, null: false
      add :rate, :decimal, null: false
    end

    create unique_index(:depot_exchange_rates, [:currency, :date])

    create table(:depot_job_runs) do
      add :name, :string, null: false
      add :ran_at, :utc_datetime_usec, null: false
      add :error, :string
    end

    create unique_index(:depot_job_runs, [:name])

    create table(:depot_compositions) do
      add :security_id, references(:depot_securities, on_delete: :delete_all), null: false
      add :countries, :map, null: false
      add :sectors, :map, null: false
      add :fetched_at, :utc_datetime_usec, null: false
    end

    create unique_index(:depot_compositions, [:security_id])

    create table(:depot_divvy_diary_dividends) do
      add :security_id, references(:depot_securities, on_delete: :delete_all), null: false
      add :ex_date, :date
      add :pay_date, :date, null: false
      add :per_share, :integer, null: false
      add :currency, :string, null: false
      add :fetched_at, :utc_datetime_usec, null: false
    end

    create index(:depot_divvy_diary_dividends, [:security_id, :pay_date])

    create table(:depot_settings) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :benchmark_id, references(:depot_securities, on_delete: :nilify_all)

      timestamps()
    end

    create unique_index(:depot_settings, [:user_id])
  end
end
