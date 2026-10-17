defmodule Abakus.Ledger.FlagMigrationTest do
  use ExUnit.Case

  alias Abakus.{Repo, TestMigrations}

  @moduletag :tmp_dir
  @before 20_261_017_160_000

  test "drops the flags and keeps the transactions", %{tmp_dir: dir} do
    repo = TestMigrations.start_repo!(dir)
    TestMigrations.run!(repo, to: @before)
    now = "'2026-10-01T10:00:00.000000Z'"

    Repo.query!("""
    INSERT INTO users (id, email, passkey_handle, inserted_at, updated_at, budget_owner)
    VALUES (1, 'owner@example.com', x'01', #{now}, #{now}, 1)
    """)

    Repo.query!("""
    INSERT INTO accounts (id, user_id, name, kind, inserted_at, updated_at)
    VALUES (1, 1, 'Giro', 'checking', #{now}, #{now})
    """)

    Repo.query!("""
    INSERT INTO transactions (id, user_id, account_id, date, amount, flag, inserted_at, updated_at)
    VALUES (1, 1, 1, '2026-10-01', -5000, 'red', #{now}, #{now})
    """)

    TestMigrations.run!(repo)

    refute ["flag"] in Repo.query!("SELECT name FROM pragma_table_info('transactions')").rows
    assert Repo.query!("SELECT id, amount FROM transactions").rows == [[1, -5000]]
  end
end
