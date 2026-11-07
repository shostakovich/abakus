defmodule Abakus.Repo.Migrations.FileAnnualReturns do
  use Ecto.Migration

  # SQLite changes a check only by rebuilding the table; nothing references the filings.
  @table "bookkeeping_filings"
  @quarter "kind IN ('vat_quarter')"
  @annual "kind IN ('vat_quarter', 'vat_year', 'euer')"

  def up do
    alter table(:bookkeeping_settings) do
      add :business_activity, :string
      add :income_kind, :string, null: false, default: "self_employment"
    end

    rebuild(@quarter, @annual)
  end

  def down do
    alter table(:bookkeeping_settings) do
      remove :business_activity
      remove :income_kind
    end

    query!(~s|DELETE FROM "#{@table}" WHERE kind <> 'vat_quarter'|)
    rebuild(@annual, @quarter)
  end

  defp rebuild(from, to) do
    [[sql]] = rows("SELECT sql FROM sqlite_master WHERE type = 'table' AND name = ?", [@table])

    indexes =
      rows(
        "SELECT sql FROM sqlite_master WHERE type = 'index' AND tbl_name = ? AND sql IS NOT NULL",
        [@table]
      )

    String.contains?(sql, "CHECK (#{from})") || raise "#{from} not found in #{sql}"
    new = @table <> "_new"

    sql
    |> String.replace(~s|CREATE TABLE "#{@table}"|, ~s|CREATE TABLE "#{new}"|)
    |> String.replace("CHECK (#{from})", "CHECK (#{to})")
    |> query!()

    query!(~s|INSERT INTO "#{new}" SELECT * FROM "#{@table}"|)
    query!(~s|DROP TABLE "#{@table}"|)
    query!(~s|ALTER TABLE "#{new}" RENAME TO "#{@table}"|)
    for [index] <- indexes, do: query!(index)
  end

  defp rows(sql, params), do: query!(sql, params).rows

  defp query!(sql, params \\ []), do: repo().query!(sql, params, log: false)
end
