defmodule Abakus.Depot.MigrationTest do
  use ExUnit.Case

  alias Abakus.Depot.Portfolios.Transaction
  alias Abakus.{Repo, TestMigrations}

  @moduletag :tmp_dir
  @before 20_261_017_200_000

  test "the imported transactions become manual and editable, the prices stay, savings plans go",
       %{tmp_dir: dir} do
    repo = TestMigrations.start_repo!(dir)
    TestMigrations.run!(repo, to: @before)
    now = "'2026-10-01T10:00:00.000000Z'"

    Repo.query!("""
    INSERT INTO users (id, email, passkey_handle, inserted_at, updated_at)
    VALUES (1, 'owner@example.com', x'01', #{now}, #{now})
    """)

    Repo.query!("""
    INSERT INTO depot_securities (id, name, pp_feed, pp_ticker, source, inserted_at, updated_at)
    VALUES (1, 'Fonds', 'YAHOO', 'VGWL.DE', 'pp_import', #{now}, #{now})
    """)

    Repo.query!("""
    INSERT INTO depot_prices (security_id, date, close, source)
    VALUES (1, '2026-09-30', 100, 'pp'), (1, '2026-10-01', 101, 'yahoo')
    """)

    Repo.query!("""
    INSERT INTO depot_accounts (id, user_id, name, currency, pp_uuid, inserted_at, updated_at)
    VALUES (1, 1, 'Verrechnungskonto', 'EUR', 'account', #{now}, #{now})
    """)

    Repo.query!("""
    INSERT INTO depot_transactions
      (id, user_id, type, date_time, account_id, amount, currency, source, pp_uuid, inserted_at, updated_at)
    VALUES (1, 1, 'deposit', '2026-09-30T12:00:00', 1, 10000, 'EUR', 'pp_import', 'deposit', #{now}, #{now})
    """)

    Repo.query!("""
    INSERT INTO depot_savings_plans
      (id, user_id, name, type, account_id, start, interval, amount, inserted_at, updated_at)
    VALUES (1, 1, 'Monatlich', 'deposit', 1, '2026-09-30', 1, 10000, #{now}, #{now})
    """)

    Repo.query!("""
    INSERT INTO depot_savings_plan_transactions (savings_plan_id, transaction_id) VALUES (1, 1)
    """)

    Repo.query!("""
    INSERT INTO depot_attribute_types (id, pp_id, name, target, inserted_at, updated_at)
    VALUES (1, 'ter', 'TER', 'Security', #{now}, #{now})
    """)

    TestMigrations.run!(repo)

    assert %Transaction{source: :manual} = transaction = Repo.get!(Transaction, 1)
    assert Transaction.editable?(transaction)

    assert Repo.query!("SELECT date, close, source FROM depot_prices ORDER BY date").rows == [
             ["2026-09-30", 100, "manual"],
             ["2026-10-01", 101, "yahoo"]
           ]

    assert Repo.query!("SELECT key FROM depot_attribute_types").rows == [["ter"]]

    refute ["pp_uuid"] in Repo.query!("SELECT name FROM pragma_table_info('depot_transactions')").rows

    refute ["source"] in Repo.query!("SELECT name FROM pragma_table_info('depot_securities')").rows

    tables = Repo.query!("SELECT name FROM sqlite_master WHERE type = 'table'").rows
    refute ["depot_savings_plans"] in tables
    refute ["depot_savings_plan_transactions"] in tables
  end
end
