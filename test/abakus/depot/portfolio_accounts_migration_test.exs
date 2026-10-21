defmodule Abakus.Depot.PortfolioAccountsMigrationTest do
  use ExUnit.Case

  alias Abakus.{Repo, TestMigrations}

  @moduletag :tmp_dir
  @before 20_261_021_200_000
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
      "3, 1, 'Old depot', 'tracking', NULL, 1",
      "4, 1, 'Gone', 'tracking', 'portfolio', 1",
      "5, 1, 'Shared', 'checking', 'shared_expenses', 0",
      "6, 1, 'Broker cash', 'tracking', NULL, 0"
    ])

    insert(
      "payees (id, user_id, name, lookup_key, transfer_account_id, inserted_at, updated_at)",
      for(
        {id, name} <- [
          {1, "Checking"},
          {2, "📈 Broker"},
          {3, "Old depot"},
          {4, "Gone"},
          {5, "Shared"},
          {6, "Broker cash"}
        ],
        do: "#{10 + id}, 1, 'Transfer : #{name}', 'transfer : #{name}', #{id}"
      ) ++ ["17, 1, 'Wertänderung', 'wertanderung', NULL"]
    )

    insert("category_groups (id, user_id, name, internal, inserted_at, updated_at)", [
      "1, 1, 'Spending', 0"
    ])

    insert(
      "categories (id, user_id, category_group_id, name, lookup_key, internal, inserted_at, updated_at)",
      ["2, 1, 1, 'Investing', 'investing', 0"]
    )

    insert("depot_securities (id, name, inserted_at, updated_at)", ["1, 'World ETF'"])

    insert(
      "depot_portfolios (id, user_id, name, retired, budget_account_id, reference_account_id, inserted_at, updated_at)",
      ["1, 1, 'Broker', 0, 2, 6", "2, 1, 'Old', 1, NULL, 6"]
    )

    insert("depot_cash_accounts (portfolio_id, account_id)", ["1, 6"])

    insert(
      "depot_transactions (id, user_id, type, date_time, account_id, portfolio_id, security_id, shares, amount, source, inserted_at, updated_at)",
      [
        "1, 1, 'deposit', '2020-01-15T12:00:00', 6, NULL, NULL, NULL, 100000, 'manual'",
        "2, 1, 'buy', '2020-02-01T12:00:00', 6, 1, 1, 100000000, 90000, 'manual'"
      ]
    )

    insert(
      "transactions (id, user_id, account_id, date, amount, payee_id, category_id, cleared, approved, source, deleted_at, inserted_at, updated_at)",
      [
        "21, 1, 1, '2020-02-01', -100000, 12, 2, 'reconciled', 1, 'ynab', NULL",
        "22, 1, 2, '2020-02-01', 100000, 11, NULL, 'reconciled', 1, 'ynab', NULL",
        "23, 1, 2, '2020-03-01', 5000, 17, NULL, 'cleared', 1, 'depot', NULL",
        "24, 1, 4, '2020-05-01', 1000, 17, NULL, 'cleared', 1, 'depot', NULL",
        "25, 1, 4, '2020-06-01', -1000, 17, NULL, 'cleared', 1, 'depot', NULL",
        "26, 1, 3, '2018-01-01', 5000, NULL, NULL, 'reconciled', 1, 'ynab', NULL",
        "27, 1, 2, '2010-01-01', 700, NULL, NULL, 'cleared', 1, 'manual', '2026-01-01T00:00:00Z'",
        "28, 1, 5, '2026-10-01', 2000, NULL, NULL, 'cleared', 0, 'kasse', NULL",
        "31, 1, 1, '2020-04-01', -30000, NULL, NULL, 'cleared', 1, 'ynab', NULL",
        "32, 1, 2, '2020-04-01', 20000, 11, NULL, 'cleared', 1, 'ynab', NULL"
      ]
    )

    insert(
      "subtransactions (id, transaction_id, position, amount, category_id, payee_id, transfer_transaction_id, inserted_at, updated_at)",
      ["41, 31, 0, -20000, 2, 12, 32", "42, 31, 1, -10000, 2, NULL, NULL"]
    )

    Repo.query!("UPDATE transactions SET transfer_transaction_id = 22 WHERE id = 21")
    Repo.query!("UPDATE transactions SET transfer_transaction_id = 21 WHERE id = 22")
    Repo.query!("UPDATE transactions SET transfer_subtransaction_id = 41 WHERE id = 32")

    insert(
      "transaction_origins (id, user_id, transaction_id, account_id, source, external_id, inserted_at, updated_at)",
      ["1, 1, 22, 2, 'ynab', 'y-22'", "2, 1, 21, 1, 'ynab', 'y-21'"]
    )

    insert(
      "bank_balances (id, user_id, account_id, source, date, amount, inserted_at, updated_at)",
      [
        "1, 1, 2, 'file', '2020-03-01', 105000"
      ]
    )

    TestMigrations.run!(repo)
    :ok
  end

  defp insert(table, values) do
    columns = table |> String.split("(") |> List.last()
    stamped? = String.contains?(columns, "inserted_at")

    for value <- values do
      value = if stamped?, do: "#{value}, #{@now}, #{@now}", else: value
      Repo.query!("INSERT INTO #{table} VALUES (#{value})")
    end
  end

  defp rows(sql, params \\ []), do: Repo.query!(sql, params).rows

  defp columns(table), do: rows("SELECT name FROM pragma_table_info(?1)", [table])

  test "removes the accounts fed by portfolio with their transactions, payees and balances" do
    assert rows("SELECT id FROM accounts ORDER BY id") == [[1], [3], [5], [6]]
    assert rows("SELECT id FROM transactions WHERE account_id IN (2, 4)") == []

    assert rows("SELECT id FROM payees WHERE transfer_account_id IN (2, 4) OR id IN (12, 14)") ==
             []

    assert rows("SELECT id FROM transaction_origins") == [[2]]
    assert rows("SELECT id FROM bank_balances") == []
  end

  test "keeps what other accounts transferred to them, as transactions with the portfolio" do
    assert [[-100_000, nil, 2, "Broker", "reconciled"]] =
             rows("""
             SELECT t.amount, t.transfer_transaction_id, t.category_id, p.name, t.cleared
             FROM transactions t JOIN payees p ON p.id = t.payee_id WHERE t.id = 21
             """)

    assert rows("""
           SELECT s.id, s.amount, s.transfer_transaction_id, s.category_id, p.name
           FROM subtransactions s LEFT JOIN payees p ON p.id = s.payee_id ORDER BY s.id
           """) == [[41, -20_000, nil, 2, "Broker"], [42, -10_000, nil, 2, nil]]

    assert rows("SELECT sum(amount) FROM transactions WHERE account_id = 1") == [[-130_000]]
  end

  test "leaves the other accounts alone, the old closed tracking account too" do
    assert rows("SELECT name, kind, closed FROM accounts WHERE id = 3") == [
             ["Old depot", "tracking", 1]
           ]

    assert rows("SELECT id, amount FROM transactions WHERE account_id = 3") == [[26, 5000]]
    assert rows("SELECT portfolio_id, account_id FROM depot_cash_accounts") == [[1, 6]]
    assert rows("SELECT count(*) FROM depot_transactions") == [[2]]
  end

  test "gives a portfolio the emoji of its account" do
    assert rows("SELECT id, name FROM depot_portfolios ORDER BY id") == [
             [1, "📈 Broker"],
             [2, "Old"]
           ]

    refute ["budget_account_id"] in columns("depot_portfolios")
    assert rows("SELECT reference_account_id FROM depot_portfolios WHERE id = 1") == [[6]]
  end

  test "marks the shared-expenses account instead of fed_by" do
    refute ["fed_by"] in columns("accounts")

    assert rows("SELECT id FROM accounts WHERE shared_expenses ORDER BY id") == [[5]]
  end
end
