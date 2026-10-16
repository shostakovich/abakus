defmodule Abakus.Repo.Migrations.AddOwnerToCategories do
  use Ecto.Migration

  # SQLite makes a column required only by rebuilding its table, with foreign keys off so a drop deletes nothing.
  @disable_ddl_transaction true
  @disable_migration_lock true

  @tables ~w(category_groups categories assignments target_versions target_snoozes)

  def up do
    refuse_without_owner!()

    with_foreign_keys_off(fn ->
      for table <- @tables do
        query!(~s|ALTER TABLE "#{table}" ADD COLUMN #{column(table)}|)
        query!(~s|UPDATE "#{table}" SET user_id = (SELECT id FROM users WHERE budget_owner)|)
      end

      # Without an owner the internal rows have nobody to belong to; each user's are created with their first use.
      query!("DELETE FROM categories WHERE user_id IS NULL AND internal")
      query!("DELETE FROM category_groups WHERE user_id IS NULL AND internal")

      for table <- @tables do
        rebuild(table, &replace!(&1, column(table), required_column(table)))
        query!(~s|CREATE INDEX "#{table}_user_id_index" ON "#{table}" ("user_id")|)
      end

      for table <- ~w(category_groups categories) do
        query!(
          ~s|CREATE UNIQUE INDEX "#{table}_internal_index" ON "#{table}" ("user_id") WHERE internal|
        )
      end
    end)
  end

  def down do
    with_foreign_keys_off(fn ->
      for table <- ~w(category_groups categories),
          do: query!(~s|DROP INDEX "#{table}_internal_index"|)

      for table <- @tables do
        query!(~s|DROP INDEX "#{table}_user_id_index"|)
        rebuild(table, &replace!(&1, ", " <> required_column(table), ""))
      end
    end)
  end

  defp refuse_without_owner! do
    used = Enum.filter(@tables, &(rows(~s|SELECT 1 FROM "#{&1}"#{own_rows(&1)} LIMIT 1|) != []))

    if used != [] and rows("SELECT 1 FROM users WHERE budget_owner") == [],
      do:
        raise(
          "No user owns the budget, so the rows of #{Enum.join(used, ", ")} would have no owner: " <>
            "set budget_owner on the budget's user first"
        )
  end

  defp own_rows(table) when table in ~w(category_groups categories), do: " WHERE NOT internal"
  defp own_rows(_table), do: ""

  defp column(table),
    do: ~s|"user_id" INTEGER CONSTRAINT "#{table}_user_id_fkey" REFERENCES "users"("id")|

  defp required_column(table),
    do: ~s|"user_id" INTEGER NOT NULL CONSTRAINT "#{table}_user_id_fkey" REFERENCES "users"("id")|

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

    # Keeps AUTOINCREMENT from reusing the ids of deleted rows.
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
