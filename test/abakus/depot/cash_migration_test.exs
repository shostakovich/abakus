defmodule Abakus.Depot.CashMigrationTest do
  use ExUnit.Case

  alias Abakus.Depot.{CashSide, Valuation}
  alias Abakus.Depot.Portfolios.Transaction
  alias Abakus.{Repo, TestMigrations}
  alias Abakus.Users.{Scope, User}

  @moduletag :tmp_dir
  @before 20_261_021_160_000
  @cash 20_261_021_180_000
  @now "'2026-10-01T10:00:00.000000Z'"

  setup %{tmp_dir: dir} do
    repo = TestMigrations.start_repo!(dir)
    TestMigrations.run!(repo, to: @before)

    insert("users (id, email, passkey_handle, budget_owner, inserted_at, updated_at)", [
      "1, 'anna@example.com', x'01', 1",
      "2, 'ben@example.com', x'02', 0"
    ])

    insert("accounts (id, user_id, name, kind, fed_by, inserted_at, updated_at)", [
      "1, 1, 'Checking', 'checking', NULL",
      "2, 1, 'Broker', 'tracking', 'portfolio'"
    ])

    insert(
      "payees (id, user_id, name, lookup_key, transfer_account_id, inserted_at, updated_at)",
      [
        "1, 1, 'Transfer : Checking', 'transfer : checking', 1",
        "2, 1, 'Transfer : Broker', 'transfer : broker', 2",
        "3, 1, 'World ETF', 'world etf', NULL"
      ]
    )

    insert("category_groups (id, user_id, name, internal, inserted_at, updated_at)", [
      "1, 1, 'Intern', 1",
      "2, 1, 'Spending', 0"
    ])

    insert(
      "categories (id, user_id, category_group_id, name, lookup_key, internal, inserted_at, updated_at)",
      [
        "1, 1, 1, 'Ready to Assign', 'ready to assign', 1",
        "2, 1, 2, 'Investing', 'investing', 0"
      ]
    )

    insert("depot_securities (id, name, inserted_at, updated_at)", ["1, 'World ETF'"])

    insert(
      "depot_portfolios (id, user_id, name, retired, budget_account_id, inserted_at, updated_at)",
      [
        "1, 1, 'Broker', 0, 2",
        "2, 1, 'Old', 1, NULL",
        "3, 2, 'Ben''s', 0, NULL"
      ]
    )

    insert(
      "depot_accounts (id, user_id, name, note, retired, budget_account_id, cash_of_portfolio_id, no_role, inserted_at, updated_at)",
      [
        "1, 1, 'Checking clearing', NULL, 0, 1, NULL, 0",
        "2, 1, 'Broker cash', 'At the broker', 0, NULL, 1, 0",
        "3, 1, 'Old cash', NULL, 0, NULL, 2, 0",
        "4, 1, 'Loose', NULL, 0, NULL, NULL, 1",
        "5, 1, 'Retired loose', NULL, 1, NULL, NULL, 1",
        "6, 2, 'Ben''s cash', NULL, 0, NULL, NULL, 1",
        "7, 1, 'Unset', NULL, 0, NULL, NULL, 0"
      ]
    )

    for {portfolio, account} <- [{1, 1}, {2, 3}, {3, 6}] do
      Repo.query!("UPDATE depot_portfolios SET reference_account_id = ?2 WHERE id = ?1", [
        portfolio,
        account
      ])
    end

    insert("depot_taxonomies (id, user_id, name, inserted_at, updated_at)", [
      "1, 1, 'Asset classes'"
    ])

    insert(
      "depot_classifications (id, taxonomy_id, name, weight, inserted_at, updated_at)",
      ["1, 1, 'Cash', 10000"]
    )

    insert("depot_assignments (id, classification_id, account_id, weight)", ["1, 1, 4, 10000"])

    insert("depot_budget_links (user_id, category_id, start_date, inserted_at, updated_at)", [
      "1, 2, '2026-09-01'"
    ])

    insert(
      "depot_transactions (id, user_id, type, date_time, account_id, other_account_id, portfolio_id, security_id, shares, amount, source, inserted_at, updated_at)",
      [
        "1, 1, 'deposit', '2026-01-10T12:00:00', 2, NULL, NULL, NULL, NULL, 100000, 'manual'",
        "2, 1, 'cash_transfer', '2026-08-01T12:00:00', 1, 2, NULL, NULL, NULL, 30000, 'manual'",
        "3, 1, 'buy', '2026-08-15T12:00:00', 1, NULL, 1, 1, 100000000, 5000, 'manual'",
        "4, 1, 'cash_transfer', '2026-09-10T12:00:00', 1, 2, NULL, NULL, NULL, 20000, 'manual'",
        "5, 1, 'buy', '2026-09-15T12:00:00', 1, NULL, 1, 1, 500000000, 50000, 'manual'",
        "6, 1, 'buy', '2026-09-20T12:00:00', 2, NULL, 1, 1, 400000000, 40000, 'manual'",
        "7, 1, 'dividend', '2026-09-25T12:00:00', 1, NULL, NULL, 1, NULL, 1500, 'manual'",
        "8, 1, 'cash_transfer', '2026-09-12T12:00:00', 1, 4, NULL, NULL, NULL, 15000, 'manual'",
        "9, 1, 'fee', '2026-09-26T12:00:00', 1, NULL, NULL, NULL, NULL, 300, 'manual'",
        "10, 1, 'deposit', '2025-02-01T12:00:00', 3, NULL, NULL, NULL, NULL, 5000, 'manual'",
        "11, 1, 'removal', '2025-03-01T12:00:00', 3, NULL, NULL, NULL, NULL, 5000, 'manual'",
        "12, 1, 'interest', '2024-01-01T12:00:00', 5, NULL, NULL, NULL, NULL, 100, 'manual'",
        "13, 2, 'deposit', '2026-05-01T12:00:00', 6, NULL, NULL, NULL, NULL, 7000, 'manual'"
      ]
    )

    # What the Depot link wrote: transfers to the portfolio's account and a dividend; then two bank lines.
    insert(
      "transactions (id, user_id, account_id, date, amount, payee_id, category_id, memo, cleared, approved, source, depot_transaction_id, inserted_at, updated_at)",
      [
        "41, 1, 1, '2026-09-10', -20000, 2, 2, 'Einzahlung', 'cleared', 1, 'depot', 4",
        "42, 1, 2, '2026-09-10', 20000, 1, NULL, 'Einzahlung', 'uncleared', 0, 'depot', NULL",
        "51, 1, 1, '2026-09-15', -50000, 2, 2, 'Kauf World ETF', 'cleared', 1, 'depot', 5",
        "52, 1, 2, '2026-09-15', 50000, 1, NULL, 'Kauf World ETF', 'uncleared', 0, 'depot', NULL",
        "71, 1, 1, '2026-09-25', 1500, 3, 1, 'Dividende', 'uncleared', 0, 'depot', 7",
        "81, 1, 1, '2026-09-14', -15000, NULL, NULL, 'Bank', 'cleared', 1, 'file', NULL",
        "82, 1, 1, '2026-09-30', -15000, NULL, NULL, 'Rent share', 'cleared', 1, 'file', NULL"
      ]
    )

    for {side, counterpart} <- [{41, 42}, {42, 41}, {51, 52}, {52, 51}] do
      Repo.query!("UPDATE transactions SET transfer_transaction_id = ?2 WHERE id = ?1", [
        side,
        counterpart
      ])
    end

    TestMigrations.run!(repo, to: @cash)
    %{repo: repo, ids: ledger_account_ids()}
  end

  defp migrate(%{repo: repo}) do
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

  defp ledger_account_ids,
    do: Map.new(rows("SELECT id, ledger_account_id FROM depot_accounts"), &List.to_tuple/1)

  defp ledger_balance(account_id) do
    [[balance]] =
      rows(
        """
        SELECT coalesce(sum(amount), 0) FROM transactions
        WHERE account_id = ?1 AND deleted_at IS NULL AND matched_transaction_id IS NULL
        """,
        [account_id]
      )

    balance
  end

  defp transactions do
    rows("""
    SELECT id, account_id, date, amount, payee_id, category_id, memo, cleared, approved, depot_transaction_id,
      transfer_transaction_id, deleted_at IS NOT NULL
    FROM transactions ORDER BY id
    """)
  end

  test "refuses to drop a Verrechnungskonto without an account in the Ledger", %{repo: repo} do
    Repo.query!("UPDATE depot_accounts SET ledger_account_id = NULL WHERE id = 4")

    assert_raise RuntimeError, ~r/no account of their user in the Ledger: Loose/, fn ->
      TestMigrations.run!(repo)
    end

    assert ["depot_accounts"] in rows("SELECT name FROM sqlite_master WHERE type = 'table'")
    assert [[4, nil]] = rows("SELECT id, ledger_account_id FROM depot_accounts WHERE id = 4")
  end

  describe "after the migrations" do
    setup :migrate

    test "maps each role to the right kind of account and closes the accounts of retired portfolios",
         %{
           ids: ids
         } do
      assert ids[1] == 1

      accounts =
        for id <- 2..7, into: %{} do
          [row] =
            rows("SELECT name, kind, closed, user_id, fed_by FROM accounts WHERE id = ?1", [
              ids[id]
            ])

          {id, row}
        end

      assert accounts == %{
               2 => ["Broker cash", "tracking", 0, 1, nil],
               3 => ["Old cash", "tracking", 1, 1, nil],
               4 => ["Loose", "tracking", 0, 1, nil],
               5 => ["Retired loose", "tracking", 1, 1, nil],
               6 => ["Ben's cash", "tracking", 0, 2, nil],
               7 => ["Unset", "tracking", 0, 1, nil]
             }

      for id <- 2..7 do
        assert [[_payee]] =
                 rows("SELECT id FROM payees WHERE transfer_account_id = ?1 AND name = ?2", [
                   ids[id],
                   "Transfer : " <> Enum.at(accounts[id], 0)
                 ])
      end
    end

    test "a tracking account's balance is the Verrechnungskonto's balance as the Depot computes it",
         %{
           ids: ids
         } do
      depot =
        Transaction
        |> Repo.all()
        |> Enum.flat_map(&Valuation.cash_moved/1)
        |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
        |> Map.new(fn {id, amounts} -> {id, Enum.sum(amounts)} end)

      for id <- 2..7, do: assert(ledger_balance(ids[id]) == Map.get(depot, ids[id], 0))
      assert ledger_balance(ids[2]) == 110_000
    end

    test "the budget account keeps the linked transactions and the bank lines, booking nothing twice",
         %{
           ids: ids
         } do
      checking =
        rows("""
        SELECT t.id, t.date, t.amount, p.name, t.category_id, t.depot_transaction_id, t.transfer_transaction_id
        FROM transactions t LEFT JOIN payees p ON p.id = t.payee_id
        WHERE t.account_id = 1 AND t.deleted_at IS NULL ORDER BY t.id
        """)

      assert [
               [41, "2026-09-10", -20_000, "Transfer : Broker cash", 2, 4, 42],
               [51, "2026-09-15", -50_000, "Broker", 2, 5, nil],
               [71, "2026-09-25", 1_500, "World ETF", 1, 7, nil],
               [81, "2026-09-12", -15_000, "Transfer : Loose", 2, 8, loose_side],
               [82, "2026-09-30", -15_000, nil, nil, nil, nil]
             ] = checking

      assert [[42, 20_000, "cleared", 1, nil]] =
               rows(
                 "SELECT id, amount, cleared, approved, category_id FROM transactions WHERE transfer_transaction_id = 41 AND account_id = ?1",
                 [ids[2]]
               )

      assert [[15_000, 81]] =
               rows("SELECT amount, transfer_transaction_id FROM transactions WHERE id = ?1", [
                 loose_side
               ])

      assert rows("SELECT id FROM transactions WHERE account_id = 2 AND deleted_at IS NULL") == []

      assert [[1, nil]] =
               rows(
                 "SELECT deleted_at IS NOT NULL, transfer_transaction_id FROM transactions WHERE id = 52"
               )
    end

    test "leaves nothing for the cash side to change" do
      before = transactions()

      for user <- Repo.all(User), do: :ok = CashSide.sync(Scope.for_user(user))

      assert transactions() == before
    end

    test "the Depot's transactions, portfolios and assignments refer to the Ledger accounts", %{
      ids: ids
    } do
      assert rows("SELECT id, account_id, other_account_id FROM depot_transactions ORDER BY id") ==
               for(
                 {id, account, other} <- [
                   {1, 2, nil},
                   {2, 1, 2},
                   {3, 1, nil},
                   {4, 1, 2},
                   {5, 1, nil},
                   {6, 2, nil},
                   {7, 1, nil},
                   {8, 1, 4},
                   {9, 1, nil},
                   {10, 3, nil},
                   {11, 3, nil},
                   {12, 5, nil},
                   {13, 6, nil}
                 ],
                 do: [id, ids[account], other && ids[other]]
               )

      assert rows("SELECT id, reference_account_id FROM depot_portfolios ORDER BY id") ==
               [[1, ids[1]], [2, ids[3]], [3, ids[6]]]

      assert rows(
               "SELECT portfolio_id, account_id FROM depot_cash_accounts ORDER BY portfolio_id"
             ) ==
               [[1, ids[2]], [2, ids[3]]]

      assert rows("SELECT account_id FROM depot_assignments") == [[ids[4]]]
      assert rows("SELECT note FROM accounts WHERE id = ?1", [ids[2]]) == [["At the broker"]]
    end

    test "drops the Verrechnungskonten" do
      refute ["depot_accounts"] in rows("SELECT name FROM sqlite_master WHERE type = 'table'")

      for table <- ~w(depot_transactions depot_portfolios depot_assignments depot_cash_accounts) do
        referenced = rows(~s|SELECT DISTINCT "table" FROM pragma_foreign_key_list(?1)|, [table])
        refute ["depot_accounts"] in referenced
      end
    end
  end
end
