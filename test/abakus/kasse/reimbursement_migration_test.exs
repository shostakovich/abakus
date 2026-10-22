defmodule Abakus.Kasse.ReimbursementMigrationTest do
  use ExUnit.Case

  import ExUnit.CaptureLog

  alias Abakus.{Repo, TestMigrations}

  @moduletag :tmp_dir
  @before 20_261_021_140_000
  @book 20_261_021_160_000
  @now "'2026-10-01T10:00:00.000000Z'"

  setup %{tmp_dir: dir} do
    repo = TestMigrations.start_repo!(dir)
    TestMigrations.run!(repo, to: @before)
    insert_link()
    %{repo: repo}
  end

  defp insert_link do
    sql!("""
    INSERT INTO users (id, email, passkey_handle, inserted_at, updated_at, budget_owner)
    VALUES (1, 'anna@example.com', x'01', #{@now}, #{@now}, 1), (2, 'ben@example.com', x'02', #{@now}, #{@now}, 0),
      (3, 'cleo@example.com', x'03', #{@now}, #{@now}, 0)
    """)

    sql!("""
    INSERT INTO kasse_participants (id, user_id, name, inserted_at, updated_at)
    VALUES (1, 1, 'Anna', #{@now}, #{@now}), (2, 2, 'Ben', #{@now}, #{@now}), (3, 3, 'Cleo', #{@now}, #{@now})
    """)

    sql!("""
    INSERT INTO accounts (id, user_id, name, kind, fed_by, inserted_at, updated_at)
    VALUES (1, 1, 'Shared', 'cash', 'shared_expenses', #{@now}, #{@now}),
      (2, 1, 'Checking', 'checking', NULL, #{@now}, #{@now}), (3, 1, 'Broker', 'tracking', NULL, #{@now}, #{@now})
    """)

    sql!("""
    INSERT INTO payees (id, user_id, name, lookup_key, transfer_account_id, inserted_at, updated_at)
    VALUES (11, 1, 'Transfer : Shared', 'transfer shared', 1, #{@now}, #{@now}),
      (12, 1, 'Transfer : Checking', 'transfer checking', 2, #{@now}, #{@now}),
      (13, 1, 'Transfer : Broker', 'transfer broker', 3, #{@now}, #{@now})
    """)

    sql!("""
    INSERT INTO kasse_budget_links (participant_id, account_id, start_date, inserted_at, updated_at)
    VALUES (1, 1, '2026-03-01', #{@now}, #{@now})
    """)
  end

  defp reimbursement!(id, date, payer, recipient, cents, opts \\ []) do
    sql!(
      """
      INSERT INTO kasse_expenses (id, title, title_folded, date, paid_by_id, reimbursement, split_mode,
        amount_cents, original_amount, original_currency, deleted_at, inserted_at, updated_at)
      VALUES (?1, 'Rückzahlung', 'rückzahlung', ?2, ?3, 1, 'equal', ?4, ?4, 'EUR', ?5, #{@now}, #{@now})
      """,
      [id, date, payer, cents, opts[:deleted_at]]
    )

    sql!(
      "INSERT INTO kasse_expense_shares (expense_id, participant_id, weight, amount_cents) VALUES (?, ?, 0, ?)",
      [id, recipient, cents]
    )
  end

  # The side in Shared gets `id`, its counterpart in the other account `id + 100`.
  defp transfer!(id, date, amount, other_account \\ 2) do
    sql!(
      """
      INSERT INTO transactions (id, user_id, account_id, date, amount, payee_id, category_id, cleared, approved,
        source, transfer_transaction_id, inserted_at, updated_at)
      VALUES (?1, 1, 1, ?2, ?3, ?4, NULL, 'reconciled', 1, 'manual', ?1 + 100, #{@now}, #{@now}),
        (?1 + 100, 1, ?5, ?2, -?3, 11, NULL, 'reconciled', 1, 'manual', ?1, #{@now}, #{@now})
      """,
      [id, date, amount, 10 + other_account, other_account]
    )
  end

  defp led_by(transaction_id),
    do: sql!("SELECT kasse_expense_id FROM transactions WHERE id = ?", [transaction_id])

  defp booked(expense_id) do
    sql!(
      """
      SELECT t.account_id, t.date, t.amount, p.name, t.category_id, t.memo, t.cleared, t.approved, t.source,
        t.transfer_transaction_id
      FROM transactions t JOIN payees p ON p.id = t.payee_id
      WHERE t.kasse_expense_id = ? AND t.deleted_at IS NULL
      """,
      [expense_id]
    )
  end

  test "the Kasse leads the reimbursements since the start date, by hand or booked anew", %{
    repo: repo
  } do
    reimbursement!(1, "2026-02-20", 1, 2, 3000)
    transfer!(1, "2026-02-20", 3000)
    reimbursement!(2, "2026-03-10", 1, 2, 3000)
    transfer!(2, "2026-03-12", 3000)
    transfer!(3, "2026-03-28", 3000)
    reimbursement!(3, "2026-03-15", 2, 1, 2500)
    reimbursement!(4, "2026-03-20", 2, 3, 1000)
    reimbursement!(5, "2026-03-22", 1, 2, 4000, deleted_at: "2026-03-23T10:00:00.000000Z")
    reimbursement!(6, "2026-03-21", 2, 1, 700)
    transfer!(4, "2026-03-21", -700, 3)

    log = capture_log(fn -> TestMigrations.run!(repo, to: @book) end)

    assert log =~
             "Kasse reimbursements in account 1, to check by hand: booked as open transactions, no transfer of " <>
               "their amount found: Kasse expense 3 (2026-03-15), Kasse expense 6 (2026-03-21); " <>
               "transfers left without a Kasse reimbursement: transaction 4 (2026-03-21), transaction 3 (2026-03-28)"

    assert led_by(1) == [[nil]]
    assert led_by(101) == [[nil]]
    assert booked(1) == []

    assert led_by(2) == [[2]]
    assert [[1, "2026-03-12", 3000, payee, nil, nil, "reconciled", 1, "manual", 102]] = booked(2)
    assert payee == "Transfer : Checking"

    assert led_by(3) == [[nil]]

    assert booked(3) == [
             [
               1,
               "2026-03-15",
               -2500,
               "Rückzahlung",
               nil,
               "Gesamt 25,00 € · bezahlt von Ben",
               "cleared",
               0,
               "kasse",
               nil
             ]
           ]

    assert booked(4) == []
    assert booked(5) == []
    assert led_by(4) == [[nil]]
    assert [[1, "2026-03-21", -700, "Rückzahlung" | _]] = booked(6)
  end

  test "pairs each transfer once, the closest dates first", %{repo: repo} do
    reimbursement!(1, "2026-03-10", 1, 2, 3000)
    reimbursement!(2, "2026-03-20", 1, 2, 3000)
    transfer!(1, "2026-03-19", 3000)
    transfer!(2, "2026-03-11", 3000)

    refute capture_log(fn -> TestMigrations.run!(repo, to: @book) end) =~ "to check by hand"

    assert led_by(2) == [[1]]
    assert led_by(1) == [[2]]
    assert sql!("SELECT count(*) FROM transactions WHERE source = 'kasse'") == [[0]]
  end

  defp sql!(sql, params \\ []), do: Repo.query!(sql, params).rows
end
