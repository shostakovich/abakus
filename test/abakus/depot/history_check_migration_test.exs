defmodule Abakus.Depot.HistoryCheckMigrationTest do
  use ExUnit.Case

  alias Abakus.{Repo, TestMigrations}

  @moduletag :tmp_dir
  @before 20_261_017_220_000
  @check 20_261_021_110_000
  @now "'2026-10-01T10:00:00.000000Z'"

  setup %{tmp_dir: dir} do
    repo = TestMigrations.start_repo!(dir)
    TestMigrations.run!(repo, to: @before)

    insert("users (id, email, passkey_handle, budget_owner, inserted_at, updated_at)", [
      "1, 'anna@example.com', x'01', 1"
    ])

    insert("accounts (id, user_id, name, kind, fed_by, closed, inserted_at, updated_at)", [
      "1, 1, 'Checking', 'checking', NULL, 0",
      "2, 1, '📈 Broker', 'tracking', 'portfolio', 0",
      "3, 1, 'Savings plan', 'tracking', 'portfolio', 0",
      "4, 1, 'Gone', 'tracking', 'portfolio', 1"
    ])

    insert(
      "depot_portfolios (id, user_id, name, retired, budget_account_id, inserted_at, updated_at)",
      [
        "1, 1, 'Broker', 0, 2",
        "2, 1, 'Plan', 0, 3"
      ]
    )

    insert("depot_accounts (id, user_id, name, cash_of_portfolio_id, inserted_at, updated_at)", [
      "1, 1, 'Broker cash', 1",
      "2, 1, 'Plan cash', 2"
    ])

    insert(
      "depot_transactions (id, user_id, type, date_time, account_id, portfolio_id, amount, source, inserted_at, updated_at)",
      [
        "1, 1, 'deposit', '2020-01-15T12:00:00', 1, NULL, 100000, 'manual'",
        "2, 1, 'buy', '2020-02-01T12:00:00', 1, 1, 90000, 'manual'",
        "3, 1, 'buy', '2022-05-01T12:00:00', 2, 2, 5000, 'manual'"
      ]
    )

    insert(
      "transactions (id, user_id, account_id, date, amount, cleared, approved, source, deleted_at, inserted_at, updated_at)",
      [
        "21, 1, 2, '2020-01-15', 100000, 'reconciled', 1, 'ynab', NULL",
        "22, 1, 3, '2022-05-01', 5000, 'cleared', 1, 'depot', NULL",
        "23, 1, 3, '2021-01-01', 700, 'cleared', 1, 'manual', '2026-01-01T00:00:00Z'",
        "24, 1, 4, '2020-05-01', 1000, 'cleared', 1, 'depot', NULL"
      ]
    )

    %{repo: repo}
  end

  defp insert(table, values) do
    for value <- values,
        do: Repo.query!("INSERT INTO #{table} VALUES (#{value}, #{@now}, #{@now})")
  end

  defp migrated?,
    do: Repo.query!("SELECT 1 FROM schema_migrations WHERE version = ?", [@check]).rows != []

  test "passes when each portfolio's Depot history reaches back as far as its account's", %{
    repo: repo
  } do
    TestMigrations.run!(repo, to: @check)

    assert migrated?()
  end

  test "counts the deposits into a portfolio's cash", %{repo: repo} do
    Repo.query!("DELETE FROM depot_transactions WHERE id = 2")

    TestMigrations.run!(repo, to: @check)

    assert migrated?()
  end

  test "refuses when an account reaches back further than its own portfolio, whatever the others",
       %{repo: repo} do
    Repo.query!("UPDATE transactions SET date = '2019-12-01' WHERE id = 21")
    Repo.query!("UPDATE transactions SET date = '2021-06-01' WHERE id = 22")

    error = assert_raise RuntimeError, fn -> TestMigrations.run!(repo, to: @check) end

    assert error.message =~
             ~s|"📈 Broker" (account 2, portfolio "Broker") from 2019-12-01, the Depot from 2020-01-15; | <>
               ~s|"Savings plan" (account 3, portfolio "Plan") from 2021-06-01, the Depot from 2022-05-01.|

    assert error.message =~ "Nothing was changed. Run the previous version"
    refute migrated?()
  end

  test "compares an account without a portfolio with the whole Depot", %{repo: repo} do
    Repo.query!("UPDATE transactions SET date = '2019-06-01' WHERE id = 24")

    assert_raise RuntimeError,
                 ~r/"Gone" \(account 4, no portfolio, so the whole Depot\) from 2019-06-01, the Depot from 2020-01-15/,
                 fn -> TestMigrations.run!(repo, to: @check) end

    Repo.query!("DELETE FROM depot_transactions")

    assert_raise RuntimeError,
                 ~r/"Gone" \(account 4, no portfolio, so the whole Depot\) from 2019-06-01, the Depot has no transactions/,
                 fn -> TestMigrations.run!(repo, to: @check) end

    refute migrated?()
  end
end
