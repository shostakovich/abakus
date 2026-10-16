defmodule Abakus.Ledger.MigrationTest do
  use ExUnit.Case

  alias Abakus.{Repo, TestMigrations}

  @moduletag :tmp_dir
  @before 20_261_017_120_000
  @tables ~w(accounts payees transactions bank_balances transaction_origins)

  setup %{tmp_dir: dir} do
    repo = TestMigrations.start_repo!(dir)
    TestMigrations.run!(repo, to: @before)
    %{repo: repo}
  end

  defp insert_budget do
    now = "'2026-10-01T10:00:00.000000Z'"

    Repo.query!("""
    INSERT INTO users (id, email, passkey_handle, inserted_at, updated_at, budget_owner)
    VALUES (1, 'kasse@example.com', x'01', #{now}, #{now}, 0),
           (2, 'owner@example.com', x'02', #{now}, #{now}, 1)
    """)

    Repo.query!("""
    INSERT INTO accounts (id, name, kind, inserted_at, updated_at)
    VALUES (1, 'Giro', 'checking', #{now}, #{now}), (2, 'Bargeld', 'cash', #{now}, #{now})
    """)

    Repo.query!("""
    INSERT INTO payees (id, name, lookup_key, transfer_account_id, inserted_at, updated_at)
    VALUES (1, 'Rewe', 'rewe', NULL, #{now}, #{now}),
           (2, 'Transfer : Bargeld', 'transfer : bargeld', 2, #{now}, #{now})
    """)

    Repo.query!("""
    INSERT INTO transactions (id, account_id, date, amount, payee_id, inserted_at, updated_at)
    VALUES (1, 1, '2026-10-01', -5000, 1, #{now}, #{now}), (2, 2, '2026-10-01', 2000, NULL, #{now}, #{now}),
           (9, 1, '2026-10-02', -100, 1, #{now}, #{now})
    """)

    Repo.query!("DELETE FROM transactions WHERE id = 9")

    Repo.query!("""
    INSERT INTO subtransactions (id, transaction_id, amount, payee_id, transfer_transaction_id, inserted_at, updated_at)
    VALUES (1, 1, -3000, NULL, NULL, #{now}, #{now}), (2, 1, -2000, 2, 2, #{now}, #{now})
    """)

    Repo.query!("UPDATE transactions SET transfer_subtransaction_id = 2 WHERE id = 2")

    Repo.query!("""
    INSERT INTO transaction_origins (transaction_id, account_id, source, external_id, inserted_at, updated_at)
    VALUES (1, 1, 'file', 'FITID1', #{now}, #{now})
    """)

    Repo.query!("""
    INSERT INTO bank_balances (account_id, source, date, amount, inserted_at, updated_at)
    VALUES (1, 'file', '2026-10-01', -5000, #{now}, #{now})
    """)
  end

  test "gives every row of the ledger to the budget owner and keeps the rest", %{repo: repo} do
    insert_budget()
    TestMigrations.run!(repo)

    for table <- @tables do
      assert Repo.query!(~s|SELECT DISTINCT user_id FROM "#{table}"|).rows == [[2]], table
    end

    assert Repo.query!("SELECT id, transaction_id, transfer_transaction_id FROM subtransactions").rows ==
             [[1, 1, nil], [2, 1, 2]]

    assert Repo.query!("SELECT transfer_subtransaction_id FROM transactions WHERE id = 2").rows ==
             [[2]]

    assert Repo.query!("SELECT seq FROM sqlite_sequence WHERE name = 'transactions'").rows == [
             [9]
           ]

    assert Repo.query!("PRAGMA foreign_keys").rows == [[1]]
  end

  test "refuses ledger rows without a budget owner and leaves the tables as they are", %{
    repo: repo
  } do
    insert_budget()
    Repo.query!("UPDATE users SET budget_owner = 0")

    assert_raise RuntimeError, ~r/No user owns the budget.*accounts, payees, transactions/, fn ->
      TestMigrations.run!(repo)
    end

    refute ["user_id"] in Repo.query!("SELECT name FROM pragma_table_info('accounts')").rows
  end

  test "requires an owner for every new row", %{repo: repo} do
    TestMigrations.run!(repo)

    assert_raise Exqlite.Error, ~r/NOT NULL constraint failed: accounts.user_id/, fn ->
      Repo.query!("""
      INSERT INTO accounts (name, kind, inserted_at, updated_at)
      VALUES ('Giro', 'checking', '2026-10-01', '2026-10-01')
      """)
    end
  end
end
