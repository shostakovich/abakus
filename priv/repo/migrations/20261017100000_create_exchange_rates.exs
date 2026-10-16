defmodule Abakus.Repo.Migrations.CreateExchangeRates do
  use Ecto.Migration

  def up do
    create table(:exchange_rates) do
      add :currency, :string, null: false
      add :date, :date, null: false
      add :source, :string, null: false
      add :rate, :decimal, null: false
    end

    create unique_index(:exchange_rates, [:currency, :source, :date])

    create table(:exchange_rate_runs) do
      add :ran_at, :utc_datetime_usec, null: false
      add :error, :string
    end

    execute """
    INSERT INTO exchange_rates (currency, date, source, rate)
    SELECT currency, date, 'ecb', rate FROM depot_exchange_rates
    """

    drop table(:depot_exchange_rates)

    alter table(:depot_job_runs) do
      remove :error
    end
  end

  def down do
    alter table(:depot_job_runs) do
      add :error, :string
    end

    create table(:depot_exchange_rates) do
      add :currency, :string, null: false
      add :date, :date, null: false
      add :rate, :decimal, null: false
    end

    create unique_index(:depot_exchange_rates, [:currency, :date])

    execute """
    INSERT INTO depot_exchange_rates (currency, date, rate)
    SELECT currency, date, rate FROM exchange_rates WHERE source = 'ecb'
    """

    drop table(:exchange_rate_runs)
    drop table(:exchange_rates)
  end
end
