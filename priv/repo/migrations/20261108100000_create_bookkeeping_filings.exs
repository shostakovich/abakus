defmodule Abakus.Repo.Migrations.CreateBookkeepingFilings do
  use Ecto.Migration

  def change do
    alter table(:bookkeeping_settings) do
      add :tax_state, :string
      add :elster_certificate, :binary
      add :elster_certificate_name, :string
    end

    create table(:bookkeeping_filings, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :user_id, references(:users, on_delete: :delete_all), null: false

      add :kind, :string,
        null: false,
        check: %{name: "bookkeeping_filings_kind_check", expr: "kind IN ('vat_quarter')"}

      add :first, :date, null: false
      add :last, :date, null: false
      add :kennzahlen, :map, null: false
      add :transfer_ticket, :string
      add :protocol, :binary
      add :sent_at, :utc_datetime_usec, null: false
      add :pending, :boolean, null: false, default: false

      timestamps()
    end

    create unique_index(:bookkeeping_filings, [:user_id, :kind, :first])
  end
end
