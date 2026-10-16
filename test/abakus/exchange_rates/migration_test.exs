defmodule Abakus.ExchangeRates.MigrationTest do
  use ExUnit.Case

  alias Abakus.ExchangeRates.ExchangeRate
  alias Abakus.{Repo, TestMigrations}

  @moduletag :tmp_dir
  @before 20_261_016_220_000

  setup %{tmp_dir: dir}, do: %{repo: TestMigrations.start_repo!(dir)}

  test "copies the Depot's ECB rates into the shared table", %{repo: repo} do
    TestMigrations.run!(repo, to: @before)

    Repo.query!("""
    INSERT INTO depot_exchange_rates (currency, date, rate)
    VALUES ('USD', '2026-10-08', '1.1186'), ('JPY', '2026-10-09', '178.15')
    """)

    TestMigrations.run!(repo)

    rates = for r <- Repo.all(ExchangeRate), do: {r.currency, r.date, r.source, r.rate}

    assert Enum.sort(rates) == [
             {"JPY", ~D[2026-10-09], :ecb, Decimal.new("178.15")},
             {"USD", ~D[2026-10-08], :ecb, Decimal.new("1.1186")}
           ]

    assert {:error, _missing} = Repo.query("SELECT 1 FROM depot_exchange_rates")
  end

  test "copies every manual rate of the Kasse and drops its table", %{repo: repo} do
    TestMigrations.run!(repo, to: 20_261_017_100_000)

    Repo.query!("""
    INSERT INTO kasse_fx_rates (currency, source, date, rate)
    VALUES ('USD', 'ecb', '2026-10-05', 1.1236), ('USD', 'manual', '2026-10-01', 1.15),
           ('USD', 'manual', '2026-10-05', 1.2), ('THB', 'manual', '2025-01-01', 38.5)
    """)

    TestMigrations.run!(repo)

    rates = for r <- Repo.all(ExchangeRate), do: {r.currency, r.date, r.source, r.rate}

    assert Enum.sort(rates) == [
             {"THB", ~D[2025-01-01], :manual, Decimal.new("38.5")},
             {"USD", ~D[2026-10-01], :manual, Decimal.new("1.15")},
             {"USD", ~D[2026-10-05], :manual, Decimal.new("1.2")}
           ]

    assert {:error, _missing} = Repo.query("SELECT 1 FROM kasse_fx_rates")
  end
end
