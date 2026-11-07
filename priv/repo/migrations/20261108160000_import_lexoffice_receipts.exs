defmodule Abakus.Repo.Migrations.ImportLexofficeReceipts do
  use Ecto.Migration

  def change do
    create table(:bookkeeping_lexoffice_receipts, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :lexoffice_id, :string, null: false
      add :number, :string
      add :date, :date, null: false
      add :contact, :string
      add :total, :integer, null: false
      add :items, :map, null: false
      add :payments, :map, null: false
      add :paperless_ids, {:array, :integer}, null: false
      add :transaction_id, references(:transactions, type: :uuid, on_delete: :nilify_all)
      add :dismissed, :boolean, null: false, default: false

      add :fixed_asset_id,
          references(:bookkeeping_fixed_assets, type: :uuid, on_delete: :nilify_all)

      add :asset_dismissed, :boolean, null: false, default: false

      timestamps()
    end

    create unique_index(:bookkeeping_lexoffice_receipts, [:user_id, :lexoffice_id])
    create index(:bookkeeping_lexoffice_receipts, [:transaction_id])
    create index(:bookkeeping_lexoffice_receipts, [:fixed_asset_id])

    alter table(:bookkeeping_filings) do
      add :filed_elsewhere, :boolean, null: false, default: false
    end
  end
end
