defmodule Abakus.Repo.Migrations.DropKasseYnab do
  use Ecto.Migration

  def up do
    drop table(:kasse_ynab_transactions)
    drop table(:kasse_ynab_category_mappings)
    drop table(:kasse_ynab_connections)
  end

  def down, do: raise(Ecto.MigrationError, "dropping the Kasse's YNAB tables is irreversible")
end
