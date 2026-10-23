defmodule Abakus.Ledger.SourceMigrationTest do
  use ExUnit.Case

  alias Abakus.{Repo, TestMigrations}

  @moduletag :tmp_dir
  @before 20_261_021_120_000
  @now "'2026-10-01T10:00:00.000000Z'"
  @deleted "'2026-10-02T10:00:00.000000Z'"

  setup %{tmp_dir: dir} do
    repo = TestMigrations.start_repo!(dir)
    TestMigrations.run!(repo, to: @before)
    insert_owner()
    %{repo: repo}
  end

  defp insert_owner do
    sql!("""
    INSERT INTO users (id, email, passkey_handle, inserted_at, updated_at, budget_owner)
    VALUES (1, 'anna@example.com', x'01', #{@now}, #{@now}, 1)
    """)

    sql!(
      "INSERT INTO kasse_participants (id, user_id, name, inserted_at, updated_at) VALUES (1, 1, 'Anna', #{@now}, #{@now})"
    )

    sql!(
      "INSERT INTO kasse_categories (id, name, inserted_at, updated_at) VALUES (90, 'Groceries', #{@now}, #{@now})"
    )

    sql!("""
    INSERT INTO accounts (id, user_id, name, kind, inserted_at, updated_at)
    VALUES (1, 1, 'Shared', 'cash', #{@now}, #{@now}), (2, 1, 'Checking', 'checking', #{@now}, #{@now})
    """)

    sql!("""
    INSERT INTO depot_portfolios (id, user_id, name, inserted_at, updated_at)
    VALUES (1, 1, 'Broker', #{@now}, #{@now})
    """)
  end

  defp expense!(id) do
    sql!(
      """
      INSERT INTO kasse_expenses (id, title, title_folded, date, category_id, paid_by_id, reimbursement, split_mode,
        amount_cents, original_amount, original_currency, inserted_at, updated_at)
      VALUES (?1, 'Market', 'market', '2026-03-01', 90, 1, 0, 'equal', 2000, 2000, 'EUR', #{@now}, #{@now})
      """,
      [id]
    )
  end

  defp depot_transaction!(id) do
    sql!(
      """
      INSERT INTO depot_transactions (id, user_id, type, date_time, portfolio_id, amount, source, inserted_at,
        updated_at)
      VALUES (?1, 1, 'buy', '2026-03-01T10:00:00', 1, 50000, 'manual', #{@now}, #{@now})
      """,
      [id]
    )
  end

  defp transaction!(id, account_id, source, deleted_at \\ "NULL") do
    sql!(
      """
      INSERT INTO transactions (id, user_id, account_id, date, amount, cleared, source, deleted_at, inserted_at,
        updated_at)
      VALUES (?1, 1, ?2, '2026-03-01', 1000, 'cleared', ?3, #{deleted_at}, #{@now}, #{@now})
      """,
      [id, account_id, source]
    )
  end

  defp kasse_link!(expense_id, transaction_id) do
    sql!(
      """
      INSERT INTO kasse_linked_transactions (expense_id, participant_id, transaction_id, written_memo, inserted_at,
        updated_at)
      VALUES (?1, 1, ?2, 'written', #{@now}, #{@now})
      """,
      [expense_id, transaction_id]
    )
  end

  defp depot_link!(depot_transaction_id, transaction_id) do
    sql!(
      """
      INSERT INTO depot_linked_transactions (user_id, depot_transaction_id, transaction_id, written_account_id,
        written_amount, written_date, inserted_at, updated_at)
      VALUES (1, ?1, ?2, 2, -50000, '2026-03-01', #{@now}, #{@now})
      """,
      [depot_transaction_id, transaction_id]
    )
  end

  defp sources do
    sql!("SELECT id, kasse_expense_id, depot_transaction_id FROM transactions ORDER BY id")
  end

  defp tables do
    sql!(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name LIKE '%linked_transactions'"
    )
  end

  test "every linked transaction refers to its expense or Depot transaction, and the link tables go",
       %{repo: repo} do
    expense!(10)
    expense!(11)
    transaction!(1, 1, "kasse")
    kasse_link!(10, 1)
    transaction!(2, 1, "kasse", @deleted)
    kasse_link!(11, 2)

    depot_transaction!(20)
    transaction!(3, 2, "depot")
    depot_link!(20, 3)
    transaction!(4, 2, "depot")
    depot_link!(nil, 4)
    transaction!(5, 2, "manual")

    TestMigrations.run!(repo)

    assert sources() == [
             [1, 10, nil],
             [2, 11, nil],
             [3, nil, 20],
             [4, nil, nil],
             [5, nil, nil]
           ]

    assert tables() == []
  end

  test "a deleted Depot transaction releases the reference of its deleted Ledger transaction", %{
    repo: repo
  } do
    depot_transaction!(20)
    transaction!(3, 2, "depot", @deleted)
    depot_link!(20, 3)

    TestMigrations.run!(repo)
    sql!("DELETE FROM depot_transactions WHERE id = 20")

    assert sources() == [[3, nil, nil]]
  end

  defp sql!(sql, params \\ []), do: Repo.query!(sql, params).rows
end
