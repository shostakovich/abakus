defmodule Abakus.Repo.Migrations.MoveKasseRatesToExchangeRates do
  use Ecto.Migration

  # The Kasse's ECB rows are left behind; the next run of the shared load fetches them again.
  def up do
    execute """
    INSERT INTO exchange_rates (currency, date, source, rate)
    SELECT currency, date, 'manual', rate FROM kasse_fx_rates WHERE source = 'manual'
    """

    drop table(:kasse_fx_rates)
  end

  def down do
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

    execute """
    INSERT INTO kasse_fx_rates (currency, source, date, rate)
    SELECT currency, 'manual', date, CAST(rate AS REAL) FROM exchange_rates WHERE source = 'manual'
    """

    execute "DELETE FROM exchange_rates WHERE source = 'manual'"
  end
end
