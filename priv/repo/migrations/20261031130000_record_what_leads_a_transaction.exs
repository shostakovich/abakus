defmodule Abakus.Repo.Migrations.RecordWhatLeadsATransaction do
  use Ecto.Migration

  def up do
    alter table(:transactions) do
      add :led_by, :string
    end

    execute "UPDATE transactions SET led_by = 'kasse' WHERE kasse_expense_id IS NOT NULL"
    execute "UPDATE transactions SET led_by = 'depot' WHERE depot_transaction_id IS NOT NULL"
  end

  def down do
    alter table(:transactions) do
      remove :led_by
    end
  end
end
