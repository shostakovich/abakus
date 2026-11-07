defmodule Abakus.Repo.Migrations.CreateBookkeepingAttachments do
  use Ecto.Migration

  def change do
    create table(:bookkeeping_attachments, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :user_id, references(:users, on_delete: :delete_all), null: false

      add :transaction_id, references(:transactions, type: :uuid, on_delete: :delete_all),
        null: false

      add :subtransaction_id,
          references(:subtransactions, type: :uuid, on_delete: :delete_all)

      add :paperless_id, :integer, null: false
      add :title, :string, null: false

      timestamps()
    end

    create unique_index(:bookkeeping_attachments, [:transaction_id, :paperless_id],
             where: "subtransaction_id IS NULL",
             name: :bookkeeping_attachments_transaction_index
           )

    create unique_index(:bookkeeping_attachments, [:subtransaction_id, :paperless_id])
    create index(:bookkeeping_attachments, [:user_id])

    create table(:bookkeeping_receipt_waivers, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :user_id, references(:users, on_delete: :delete_all), null: false

      add :transaction_id, references(:transactions, type: :uuid, on_delete: :delete_all),
        null: false

      timestamps()
    end

    create unique_index(:bookkeeping_receipt_waivers, [:transaction_id])
    create index(:bookkeeping_receipt_waivers, [:user_id])
  end
end
