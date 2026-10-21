defmodule Abakus.Repo.Migrations.PointTheDepotAtLedgerAccounts do
  use Ecto.Migration

  # SQLite changes a foreign key only by rebuilding its table, with foreign keys off so a drop deletes nothing.
  @disable_ddl_transaction true
  @disable_migration_lock true

  @references [
    {"depot_transactions", ~w(account_id other_account_id)},
    {"depot_portfolios", ~w(reference_account_id)},
    {"depot_assignments", ~w(account_id)}
  ]

  def up do
    with_foreign_keys_off(fn ->
      refuse_unmapped!()
      create_cash_accounts()
      keep_notes()

      for {table, columns} <- @references do
        for column <- columns, do: remap(table, column)
        rebuild(table, &point_at_accounts(table, &1))
      end

      query!(~s|DROP TABLE "depot_accounts"|)
    end)
  end

  def down,
    do: raise(Ecto.MigrationError, "pointing the Depot at the Ledger's accounts is irreversible")

  defp refuse_unmapped! do
    unmapped =
      rows("""
      SELECT d.name FROM depot_accounts d LEFT JOIN accounts a ON a.id = d.ledger_account_id
      WHERE a.id IS NULL OR a.user_id != d.user_id ORDER BY d.id
      """)

    if unmapped != [],
      do:
        raise(
          "These Verrechnungskonten have no account of their user in the Ledger: " <>
            Enum.map_join(unmapped, ", ", &hd/1)
        )
  end

  defp create_cash_accounts do
    query!("""
    CREATE TABLE "depot_cash_accounts" (
      "portfolio_id" INTEGER NOT NULL CONSTRAINT "depot_cash_accounts_portfolio_id_fkey"
        REFERENCES "depot_portfolios"("id") ON DELETE CASCADE,
      "account_id" INTEGER NOT NULL CONSTRAINT "depot_cash_accounts_account_id_fkey"
        REFERENCES "accounts"("id") ON DELETE CASCADE
    )
    """)

    query!(
      ~s|CREATE UNIQUE INDEX "depot_cash_accounts_account_id_index" ON "depot_cash_accounts" ("account_id")|
    )

    query!(
      ~s|CREATE INDEX "depot_cash_accounts_portfolio_id_index" ON "depot_cash_accounts" ("portfolio_id")|
    )

    query!("""
    INSERT INTO depot_cash_accounts (portfolio_id, account_id)
    SELECT cash_of_portfolio_id, ledger_account_id FROM depot_accounts WHERE cash_of_portfolio_id IS NOT NULL
    """)
  end

  defp keep_notes do
    query!("""
    UPDATE accounts SET note = (SELECT d.note FROM depot_accounts d WHERE d.ledger_account_id = accounts.id)
    WHERE coalesce(note, '') = ''
      AND EXISTS (SELECT 1 FROM depot_accounts d WHERE d.ledger_account_id = accounts.id AND coalesce(d.note, '') != '')
    """)
  end

  defp remap(table, column) do
    query!("""
    UPDATE "#{table}" SET "#{column}" = (SELECT ledger_account_id FROM depot_accounts WHERE id = "#{table}"."#{column}")
    WHERE "#{column}" IS NOT NULL
    """)
  end

  # Deleting a Ledger account must not delete the Depot's history with it.
  defp point_at_accounts("depot_transactions", sql),
    do:
      replace!(
        sql,
        ~s|REFERENCES "depot_accounts"("id") ON DELETE CASCADE|,
        ~s|REFERENCES "accounts"("id")|
      )

  defp point_at_accounts(_table, sql),
    do: replace!(sql, ~s|REFERENCES "depot_accounts"("id")|, ~s|REFERENCES "accounts"("id")|)

  # SQLite's procedure for other schema changes: copy into a new table, drop the old one, rename, re-index.
  defp rebuild(table, change) do
    [[sql]] = rows("SELECT sql FROM sqlite_master WHERE type = 'table' AND name = ?", [table])

    indexes =
      rows(
        "SELECT sql FROM sqlite_master WHERE type = 'index' AND tbl_name = ? AND sql IS NOT NULL",
        [table]
      )

    sequence = rows("SELECT seq FROM sqlite_sequence WHERE name = ?", [table])
    new = table <> "_new"

    sql
    |> replace!(~s|CREATE TABLE "#{table}"|, ~s|CREATE TABLE "#{new}"|)
    |> change.()
    |> query!()

    columns =
      rows("SELECT name FROM pragma_table_info(?)", [new])
      |> Enum.map_join(", ", &~s|"#{hd(&1)}"|)

    query!(~s|INSERT INTO "#{new}" (#{columns}) SELECT #{columns} FROM "#{table}"|)
    query!(~s|DROP TABLE "#{table}"|)
    query!(~s|ALTER TABLE "#{new}" RENAME TO "#{table}"|)
    for [index] <- indexes, do: query!(index)

    for [seq] <- sequence,
        do: query!("UPDATE sqlite_sequence SET seq = ? WHERE name = ?", [seq, table])
  end

  defp with_foreign_keys_off(fun) do
    repo().checkout(fn ->
      query!("PRAGMA foreign_keys = OFF")

      try do
        repo().transaction(fn ->
          fun.()

          with [_ | _] = broken <- rows("PRAGMA foreign_key_check"),
               do: raise("Broken foreign keys: #{inspect(broken)}")
        end)
      after
        query!("PRAGMA foreign_keys = ON")
      end
    end)
  end

  defp replace!(string, pattern, replacement) do
    if String.contains?(string, pattern),
      do: String.replace(string, pattern, replacement),
      else: raise("#{inspect(pattern)} not found in #{string}")
  end

  defp rows(sql, params \\ []), do: query!(sql, params).rows

  defp query!(sql, params \\ []), do: repo().query!(sql, params, log: false)
end
