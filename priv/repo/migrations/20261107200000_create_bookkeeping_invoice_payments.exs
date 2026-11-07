defmodule Abakus.Repo.Migrations.CreateBookkeepingInvoicePayments do
  use Ecto.Migration

  def change do
    create table(:bookkeeping_invoice_payments, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :user_id, references(:users, on_delete: :delete_all), null: false

      add :invoice_id, references(:bookkeeping_invoices, type: :uuid, on_delete: :delete_all),
        null: false

      add :transaction_id, references(:transactions, type: :uuid, on_delete: :delete_all),
        null: false

      timestamps()
    end

    create unique_index(:bookkeeping_invoice_payments, [:invoice_id])
    create unique_index(:bookkeeping_invoice_payments, [:transaction_id])
    create index(:bookkeeping_invoice_payments, [:user_id])
  end
end
