defmodule Abakus.Repo.Migrations.DropScheduledTransactionsDaysCheck do
  use Ecto.Migration

  # Messages merged field by field may leave a frequency without its days. SQLite drops a check only by rebuilding
  # the table, with foreign keys off so the drop deletes no parts.
  @disable_ddl_transaction true
  @disable_migration_lock true

  @table "scheduled_transactions"
  @column ~s|"second_day" INTEGER|
  @check ~r/ CONSTRAINT scheduled_transactions_days_check CHECK \(CASE .*? END\s*\)/s

  @days """
   CONSTRAINT scheduled_transactions_days_check CHECK (CASE WHEN frequency = 'twice_a_month'
    THEN coalesce(first_day BETWEEN 1 AND 30 AND second_day BETWEEN first_day + 1 AND 31, 0)
    ELSE first_day IS NULL AND second_day IS NULL END
  )\
  """

  def up do
    with_foreign_keys_off(fn ->
      rebuild(fn sql ->
        if Regex.match?(@check, sql),
          do: Regex.replace(@check, sql, ""),
          else: raise("scheduled_transactions_days_check not found in #{sql}")
      end)
    end)
  end

  def down do
    with_foreign_keys_off(fn ->
      rebuild(&String.replace(&1, @column, @column <> @days, global: false))
    end)
  end

  defp rebuild(change) do
    [[sql]] = rows("SELECT sql FROM sqlite_master WHERE type = 'table' AND name = ?", [@table])

    indexes =
      rows(
        "SELECT sql FROM sqlite_master WHERE type = 'index' AND tbl_name = ? AND sql IS NOT NULL",
        [@table]
      )

    new = @table <> "_new"

    sql
    |> String.replace(~s|CREATE TABLE "#{@table}"|, ~s|CREATE TABLE "#{new}"|)
    |> change.()
    |> query!()

    columns =
      rows("SELECT name FROM pragma_table_info(?)", [new])
      |> Enum.map_join(", ", &~s|"#{hd(&1)}"|)

    query!(~s|INSERT INTO "#{new}" (#{columns}) SELECT #{columns} FROM "#{@table}"|)
    query!(~s|DROP TABLE "#{@table}"|)
    query!(~s|ALTER TABLE "#{new}" RENAME TO "#{@table}"|)
    for [index] <- indexes, do: query!(index)
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

  defp rows(sql, params \\ []), do: query!(sql, params).rows

  defp query!(sql, params \\ []), do: repo().query!(sql, params, log: false)
end
