defmodule Abakus.ExchangeRates.MigrationTest do
  use ExUnit.Case

  alias Abakus.ExchangeRates.ExchangeRate
  alias Abakus.{Repo, TestMigrations}

  @moduletag :tmp_dir
  @before 20_261_016_220_000

  setup %{tmp_dir: dir} do
    path = Path.join(dir, "abakus.sqlite3")

    repo =
      start_supervised!(
        {Repo, name: nil, database: path, pool: DBConnection.ConnectionPool, pool_size: 1},
        id: {Repo, path}
      )

    Repo.put_dynamic_repo(repo)
    on_exit(fn -> Repo.put_dynamic_repo(Repo) end)
    %{repo: repo}
  end

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
end
