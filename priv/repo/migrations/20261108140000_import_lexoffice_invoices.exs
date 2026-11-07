defmodule Abakus.Repo.Migrations.ImportLexofficeInvoices do
  use Ecto.Migration

  def change do
    alter table(:bookkeeping_invoices) do
      add :lexoffice_id, :string
      add :paperless_id, :integer
      add :paid_on, :date
      add :voided, :boolean, null: false, default: false
    end

    alter table(:bookkeeping_customers) do
      add :lexoffice_id, :string
    end

    create unique_index(:bookkeeping_invoices, [:user_id, :lexoffice_id])
    create unique_index(:bookkeeping_customers, [:user_id, :lexoffice_id])
  end
end
