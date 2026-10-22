defmodule Abakus.Repo.Migrations.MoveLinksToTheirSource do
  use Ecto.Migration

  def up do
    alter table(:transactions) do
      add :kasse_expense_id, references(:kasse_expenses)
      add :depot_transaction_id, references(:depot_transactions, on_delete: :nilify_all)
    end

    flush()

    execute("""
    UPDATE transactions SET kasse_expense_id =
      (SELECT l.expense_id FROM kasse_linked_transactions l WHERE l.transaction_id = transactions.id)
    WHERE id IN (SELECT transaction_id FROM kasse_linked_transactions)
    """)

    execute("""
    UPDATE transactions SET depot_transaction_id =
      (SELECT l.depot_transaction_id FROM depot_linked_transactions l WHERE l.transaction_id = transactions.id)
    WHERE id IN (SELECT transaction_id FROM depot_linked_transactions WHERE depot_transaction_id IS NOT NULL)
    """)

    create unique_index(:transactions, [:kasse_expense_id, :user_id],
             where: "kasse_expense_id IS NOT NULL AND deleted_at IS NULL"
           )

    create unique_index(:transactions, [:depot_transaction_id],
             where: "depot_transaction_id IS NOT NULL AND deleted_at IS NULL"
           )

    drop table(:kasse_linked_transactions)
    drop table(:depot_linked_transactions)
  end

  def down,
    do: raise(Ecto.MigrationError, "moving the links to their source is irreversible")
end
