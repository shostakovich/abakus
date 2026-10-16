defmodule Abakus.Repo.Migrations.CreateDepotReceipts do
  use Ecto.Migration

  def change do
    create table(:depot_receipts) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :sha256, :string, null: false
      add :filename, :string, null: false
      add :byte_size, :integer, null: false
      add :status, :string, null: false, default: "booked"
      add :text, :text
      add :fields, :map
      add :checks, :map
      add :bank_reference, :string
      add :paperless_id, :integer

      timestamps()
    end

    create unique_index(:depot_receipts, [:user_id, :sha256])
    create index(:depot_receipts, [:user_id, :status])
    create index(:depot_receipts, [:user_id, :bank_reference])
    create index(:depot_receipts, [:user_id, :paperless_id])

    alter table(:depot_transactions) do
      add :receipt_id, references(:depot_receipts, on_delete: :nilify_all)
    end

    create index(:depot_transactions, [:receipt_id])

    alter table(:depot_settings) do
      add :paperless_url, :string
      add :paperless_token, :string
      add :paperless_tag, :string
      add :paperless_polled_at, :utc_datetime_usec
    end
  end
end
