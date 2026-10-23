defmodule Abakus.Repo.Migrations.RemovePortfolioAccounts do
  use Ecto.Migration

  # SQLite drops a foreign key column only by rebuilding its table, with foreign keys off so a drop deletes nothing.
  @disable_ddl_transaction true
  @disable_migration_lock true

  @portfolio_accounts "SELECT id FROM accounts WHERE fed_by = 'portfolio'"
  @their_transactions "SELECT id FROM transactions WHERE account_id IN (#{@portfolio_accounts})"
  @their_subtransactions "SELECT id FROM subtransactions WHERE transaction_id IN (#{@their_transactions})"

  def up do
    with_foreign_keys_off(fn ->
      now = DateTime.to_iso8601(DateTime.utc_now())
      keep_emoji(now)
      for account <- portfolio_accounts(), do: release_counterparts(account, now)
      delete_portfolio_accounts()
      drop_budget_account_id()
      mark_shared_expenses()
    end)
  end

  def down,
    do: raise(Ecto.MigrationError, "removing the portfolio accounts is irreversible")

  defp keep_emoji(now) do
    for [id, name, account_name] <-
          rows("""
          SELECT p.id, p.name, a.name FROM depot_portfolios p JOIN accounts a ON a.id = p.budget_account_id
          """),
        {emoji, _rest} = split_emoji(account_name),
        emoji != nil and elem(split_emoji(name), 0) == nil,
        do:
          query!("UPDATE depot_portfolios SET name = ?2, updated_at = ?3 WHERE id = ?1", [
            id,
            "#{emoji} #{name}",
            now
          ])
  end

  defp portfolio_accounts do
    for [id, user_id, name, transfer_payee_id] <-
          rows("""
          SELECT a.id, a.user_id, a.name, p.id FROM accounts a LEFT JOIN payees p ON p.transfer_account_id = a.id
          WHERE a.fed_by = 'portfolio'
          """),
        do: %{id: id, user_id: user_id, name: name, transfer_payee_id: transfer_payee_id}
  end

  # What other accounts transferred to a portfolio account stays, as a transaction with the portfolio.
  defp release_counterparts(account, now) do
    payee_id = payee_id(account, now)
    sides = "SELECT id FROM transactions WHERE account_id = ?1"
    split_sides = "SELECT id FROM subtransactions WHERE transaction_id IN (#{sides})"

    query!(
      """
      UPDATE transactions SET transfer_transaction_id = NULL, transfer_subtransaction_id = NULL, payee_id = ?2,
        updated_at = ?3
      WHERE account_id != ?1
        AND (transfer_transaction_id IN (#{sides}) OR transfer_subtransaction_id IN (#{split_sides}) OR payee_id = ?4)
      """,
      [account.id, payee_id, now, account.transfer_payee_id]
    )

    query!(
      """
      UPDATE subtransactions SET transfer_transaction_id = NULL, payee_id = ?2, updated_at = ?3
      WHERE transaction_id NOT IN (#{sides}) AND (transfer_transaction_id IN (#{sides}) OR payee_id = ?4)
      """,
      [account.id, payee_id, now, account.transfer_payee_id]
    )

    query!(
      "UPDATE transactions SET matched_transaction_id = NULL, updated_at = ?2 WHERE account_id != ?1 AND matched_transaction_id IN (#{sides})",
      [account.id, now]
    )
  end

  defp payee_id(account, now) do
    {_emoji, name} = split_emoji(account.name)
    key = lookup_key(name)

    case rows(
           "SELECT id FROM payees WHERE user_id = ?1 AND lookup_key = ?2 AND transfer_account_id IS NULL",
           [account.user_id, key]
         ) do
      [[id]] ->
        id

      [] ->
        [[id]] =
          rows(
            """
            INSERT INTO payees (user_id, name, lookup_key, inserted_at, updated_at) VALUES (?1, ?2, ?3, ?4, ?4)
            RETURNING id
            """,
            [account.user_id, name, key, now]
          )

        id
    end
  end

  defp delete_portfolio_accounts do
    query!("DELETE FROM transaction_origins WHERE account_id IN (#{@portfolio_accounts})")
    query!("DELETE FROM transaction_origins WHERE transaction_id IN (#{@their_transactions})")
    query!("DELETE FROM bank_balances WHERE account_id IN (#{@portfolio_accounts})")

    query!(
      "UPDATE transactions SET transfer_subtransaction_id = NULL WHERE transfer_subtransaction_id IN (#{@their_subtransactions})"
    )

    query!("DELETE FROM subtransactions WHERE transaction_id IN (#{@their_transactions})")
    query!("DELETE FROM transactions WHERE account_id IN (#{@portfolio_accounts})")
    query!("DELETE FROM payees WHERE transfer_account_id IN (#{@portfolio_accounts})")
    query!("DELETE FROM accounts WHERE fed_by = 'portfolio'")
  end

  defp drop_budget_account_id do
    query!(~s|DROP INDEX "depot_portfolios_budget_account_id_index"|)

    rebuild(
      "depot_portfolios",
      &replace!(
        &1,
        ~s|, "budget_account_id" INTEGER CONSTRAINT "depot_portfolios_budget_account_id_fkey" REFERENCES "accounts"("id") ON DELETE SET NULL|,
        ""
      )
    )
  end

  defp mark_shared_expenses do
    query!(~s|ALTER TABLE "accounts" ADD COLUMN "shared_expenses" INTEGER DEFAULT false NOT NULL|)
    query!("UPDATE accounts SET shared_expenses = true WHERE fed_by = 'shared_expenses'")
    query!(~s|ALTER TABLE "accounts" DROP COLUMN "fed_by"|)
  end

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

  # Copies of Abakus.Names: a migration must not change with the app.
  defp lookup_key(name) do
    name = :unicode.characters_to_nfc_binary(name)

    with "" <- normalize(Regex.replace(emoji(), name, " ")),
         "" <- normalize(Regex.replace(~r/[\x{FE0E}\x{FE0F}\x{1F3FB}-\x{1F3FF}]/u, name, "")) do
      normalize(name)
    end
  end

  defp normalize(name) do
    ~r/\s+/u
    |> Regex.replace(name, " ")
    |> String.trim()
    |> String.downcase()
    |> String.replace("ß", "ss")
  end

  defp split_emoji(name) do
    emoji = Regex.source(emoji())

    case Regex.run(~r/^((?:#{emoji})+)\s*((?!#{emoji})\S.*)$/xsu, name) do
      [_, leading, rest] -> {leading, rest}
      nil -> {nil, name}
    end
  end

  defp emoji do
    ~r/
      [0-9#*]\x{FE0F}?\x{20E3}
      | [\p{So}\p{Extended_Pictographic}\p{Emoji_Modifier}\p{Regional_Indicator}]
      | [\x{200D}\x{FE0E}\x{FE0F}\x{20E3}\x{E0020}-\x{E007F}]
    /ux
  end

  defp rows(sql, params \\ []), do: query!(sql, params).rows

  defp query!(sql, params \\ []), do: repo().query!(sql, params, log: false)
end
