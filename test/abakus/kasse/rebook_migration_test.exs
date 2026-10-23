defmodule Abakus.Kasse.RebookMigrationTest do
  use ExUnit.Case

  alias Abakus.{Repo, TestMigrations}

  @moduletag :tmp_dir
  @before 20_261_017_220_000
  @rebook 20_261_021_120_000
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
    VALUES (1, 'anna@example.com', x'01', #{@now}, #{@now}, 1), (2, 'ben@example.com', x'02', #{@now}, #{@now}, 0)
    """)

    sql!("""
    INSERT INTO kasse_participants (id, user_id, name, inserted_at, updated_at)
    VALUES (1, 1, 'Anna', #{@now}, #{@now}), (2, 2, 'Ben', #{@now}, #{@now})
    """)

    sql!("""
    INSERT INTO category_groups (id, user_id, name, inserted_at, updated_at) VALUES (1, 1, 'Daily', #{@now}, #{@now})
    """)

    sql!("""
    INSERT INTO categories (id, user_id, category_group_id, name, lookup_key, inserted_at, updated_at)
    VALUES (7, 1, 1, 'Food', 'food', #{@now}, #{@now})
    """)

    sql!(
      "INSERT INTO kasse_categories (id, name, inserted_at, updated_at) VALUES (90, 'Groceries', #{@now}, #{@now})"
    )

    sql!(
      "INSERT INTO kasse_budget_category_mappings (category_id, budget_category_id) VALUES (90, 7)"
    )

    sql!("""
    INSERT INTO accounts (id, user_id, name, kind, fed_by, inserted_at, updated_at)
    VALUES (1, 1, 'Shared', 'cash', 'shared_expenses', #{@now}, #{@now})
    """)

    sql!("""
    INSERT INTO kasse_budget_links (participant_id, account_id, start_date, inserted_at, updated_at)
    VALUES (1, 1, '2026-03-01', #{@now}, #{@now})
    """)

    sql!("""
    INSERT INTO payees (id, user_id, name, lookup_key, inserted_at, updated_at)
    VALUES (1, 1, 'Market', 'market', #{@now}, #{@now})
    """)
  end

  defp expense!(id, title, date, paid_by, cents, shares, opts \\ []) do
    {original, currency} = Keyword.get(opts, :original, {cents, "EUR"})

    sql!(
      """
      INSERT INTO kasse_expenses (id, title, title_folded, date, category_id, paid_by_id, reimbursement, split_mode,
        amount_cents, original_amount, original_currency, deleted_at, inserted_at, updated_at)
      VALUES (?1, ?2, ?2, ?3, 90, ?4, ?5, 'equal', ?6, ?7, ?8, ?9, #{@now}, #{@now})
      """,
      [
        id,
        title,
        date,
        paid_by,
        if(opts[:reimbursement], do: 1, else: 0),
        cents,
        original,
        currency,
        opts[:deleted_at]
      ]
    )

    for {participant, share} <- shares do
      sql!(
        "INSERT INTO kasse_expense_shares (expense_id, participant_id, weight, amount_cents) VALUES (?, ?, 1, ?)",
        [id, participant, share]
      )
    end
  end

  defp linked!(expense_id, amount, opts \\ []) do
    sql!(
      """
      INSERT INTO transactions (id, user_id, account_id, date, amount, payee_id, category_id, memo, cleared, source,
        deleted_at, inserted_at, updated_at)
      SELECT ?1, 1, 1, date, ?2, 1, 7, 'written', 'cleared', 'kasse', ?3, #{@now}, #{@now}
      FROM kasse_expenses WHERE id = ?1
      """,
      [expense_id, amount, opts[:deleted_at]]
    )

    sql!(
      """
      INSERT INTO kasse_linked_transactions (expense_id, participant_id, transaction_id, written_category_id,
        written_memo, inserted_at, updated_at)
      VALUES (?1, 1, ?1, 7, 'written', #{@now}, #{@now})
      """,
      [expense_id]
    )
  end

  defp transaction(expense_id) do
    case sql!(
           """
           SELECT t.amount, t.deleted_at IS NOT NULL FROM kasse_linked_transactions l
           JOIN transactions t ON t.id = l.transaction_id WHERE l.expense_id = ?
           """,
           [expense_id]
         ) do
      [[amount, deleted?]] -> {amount, deleted? == 1}
      [] -> nil
    end
  end

  test "rebooks every linked expense as paid minus share and books the missing ones since the start date",
       %{
         repo: repo
       } do
    expense!(1, "Old", "2026-02-10", 1, 2000, [{1, 1000}, {2, 1000}])
    linked!(1, -1000)
    expense!(9, "Older", "2026-02-11", 1, 2000, [{1, 1000}, {2, 1000}])

    expense!(10, "Gone", "2026-03-08", 1, 2000, [{1, 1000}, {2, 1000}],
      deleted_at: "2026-03-09T10:00:00.000000Z"
    )

    linked!(10, -1000)
    expense!(2, "Market", "2026-03-01", 1, 2000, [{1, 1000}, {2, 1000}])
    linked!(2, -1000)
    expense!(3, "Cinema", "2026-03-02", 2, 2400, [{1, 1200}, {2, 1200}])
    linked!(3, -1200)
    expense!(4, "Bakery", "2026-03-03", 1, 500, [{1, 500}])
    linked!(4, -500)
    expense!(5, "Gift", "2026-03-04", 1, 1200, [{2, 1200}], original: {1500, "USD"})
    expense!(6, "Bar", "2026-03-05", 2, 3000, [{2, 3000}])
    expense!(7, "Rückzahlung", "2026-03-06", 1, 1000, [{2, 1000}], reimbursement: true)
    expense!(8, "Deleted", "2026-03-07", 1, 2000, [{1, 1000}, {2, 1000}])
    linked!(8, -1000, deleted_at: "2026-03-08T10:00:00.000000Z")

    TestMigrations.run!(repo, to: @rebook)

    assert transaction(1) == {1000, false}
    assert transaction(9) == nil
    assert transaction(10) == {-1000, false}
    assert transaction(2) == {1000, false}
    assert transaction(3) == {-1200, false}
    assert transaction(4) == nil
    assert sql!("SELECT deleted_at IS NOT NULL FROM transactions WHERE id = 4") == [[1]]
    assert transaction(5) == {1200, false}
    assert transaction(6) == nil
    assert transaction(7) == nil
    assert transaction(8) == {-1000, true}

    assert [
             [
               1,
               "2026-03-04",
               7,
               "Gesamt 12,00 € (15,00 USD) · bezahlt von Anna",
               "cleared",
               0,
               "kasse",
               "Gift",
               7
             ]
           ] =
             sql!("""
             SELECT t.account_id, t.date, t.category_id, t.memo, t.cleared, t.approved, t.source, p.name,
               p.last_category_id
             FROM kasse_linked_transactions l JOIN transactions t ON t.id = l.transaction_id
             JOIN payees p ON p.id = t.payee_id WHERE l.expense_id = 5
             """)

    assert sql!(
             "SELECT written_category_id, written_memo FROM kasse_linked_transactions WHERE expense_id = 5"
           ) ==
             [[7, "Gesamt 12,00 € (15,00 USD) · bezahlt von Anna"]]
  end

  test "rebooks every expense of a link without a start date and finds the payee by name", %{
    repo: repo
  } do
    sql!("UPDATE kasse_budget_links SET start_date = NULL")
    expense!(1, "Old", "2026-02-10", 1, 2000, [{1, 1000}, {2, 1000}])
    linked!(1, -1000)
    expense!(2, "🛒 MARKET", "2026-02-11", 1, 1000, [{2, 1000}])

    TestMigrations.run!(repo, to: @rebook)

    assert transaction(1) == {1000, false}
    assert transaction(2) == {1000, false}

    assert sql!(
             "SELECT payee_id FROM transactions t JOIN kasse_linked_transactions l ON t.id = l.transaction_id WHERE l.expense_id = 2"
           ) == [[1]]
  end

  defp sql!(sql, params \\ []), do: Repo.query!(sql, params).rows
end
