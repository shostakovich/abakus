defmodule Abakus.Repo.Migrations.CreateTransactions do
  use Ecto.Migration

  def change do
    create table(:transactions) do
      add :account_id, references(:accounts, on_delete: :restrict), null: false
      add :date, :date, null: false
      add :amount, :integer, null: false
      add :payee_id, references(:payees, on_delete: :restrict)
      add :category_id, references(:categories, on_delete: :restrict)
      add :memo, :text
      add :cleared, :string, null: false, default: "uncleared"
      add :approved, :boolean, null: false, default: false
      add :flag, :string
      add :transfer_transaction_id, references(:transactions, on_delete: :restrict)

      # The counterpart of a split's subtransaction points to it; SQLite resolves the table when writing.
      add :transfer_subtransaction_id, references(:subtransactions, on_delete: :restrict),
        check: %{
          name: "transactions_one_transfer_side",
          expr: "transfer_transaction_id IS NULL OR transfer_subtransaction_id IS NULL"
        }

      add :source, :string, null: false, default: "manual"
      add :matched_transaction_id, references(:transactions, on_delete: :restrict)
      add :deleted_at, :utc_datetime_usec

      timestamps()
    end

    create index(:transactions, [:account_id, :date])
    create index(:transactions, [:category_id])
    create index(:transactions, [:payee_id])

    for column <- [:transfer_transaction_id, :transfer_subtransaction_id, :matched_transaction_id] do
      create unique_index(:transactions, [column], where: "#{column} IS NOT NULL")
    end

    create table(:subtransactions) do
      add :transaction_id, references(:transactions, on_delete: :delete_all), null: false
      add :position, :integer, null: false, default: 0
      add :amount, :integer, null: false
      add :category_id, references(:categories, on_delete: :restrict)
      add :payee_id, references(:payees, on_delete: :restrict)
      add :memo, :text
      add :transfer_transaction_id, references(:transactions, on_delete: :restrict)

      timestamps()
    end

    create index(:subtransactions, [:transaction_id, :position])
    create index(:subtransactions, [:category_id])
    create index(:subtransactions, [:payee_id])

    create unique_index(:subtransactions, [:transfer_transaction_id],
             where: "transfer_transaction_id IS NOT NULL"
           )

    # SQLite checks foreign keys when a rollback drops tables with rows, so the pointers go first.
    execute(
      fn -> :ok end,
      """
      UPDATE transactions
      SET transfer_transaction_id = NULL, transfer_subtransaction_id = NULL, matched_transaction_id = NULL
      """
    )

    create table(:transaction_origins) do
      add :transaction_id, references(:transactions, on_delete: :delete_all), null: false
      add :account_id, references(:accounts, on_delete: :restrict), null: false
      add :source, :string, null: false
      add :external_id, :string, null: false

      timestamps()
    end

    create index(:transaction_origins, [:transaction_id])
    create unique_index(:transaction_origins, [:account_id, :source, :external_id])
  end
end
