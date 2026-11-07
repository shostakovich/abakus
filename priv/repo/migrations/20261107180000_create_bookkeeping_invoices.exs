defmodule Abakus.Repo.Migrations.CreateBookkeepingInvoices do
  use Ecto.Migration

  def change do
    create table(:bookkeeping_settings, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :name, :string
      add :street, :string
      add :postal_code, :string
      add :city, :string
      add :vat_id, :string
      add :tax_number, :string
      add :iban, :string
      add :payment_days, :integer, null: false, default: 14

      timestamps()
    end

    create unique_index(:bookkeeping_settings, [:user_id])

    create table(:bookkeeping_customers, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :street, :string
      add :postal_code, :string
      add :city, :string
      add :country, :string, null: false, default: "DE"
      add :vat_id, :string

      timestamps()
    end

    create index(:bookkeeping_customers, [:user_id])

    create table(:bookkeeping_invoices, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :user_id, references(:users, on_delete: :delete_all), null: false

      add :customer_id, references(:bookkeeping_customers, type: :uuid, on_delete: :restrict),
        null: false

      add :number, :string, null: false
      add :counter, :integer, null: false
      add :date, :date, null: false
      add :service_from, :date, null: false
      add :service_to, :date, null: false
      add :due_date, :date, null: false

      add :vat, :string,
        null: false,
        check: %{
          name: "bookkeeping_invoices_vat_check",
          expr: "vat IN ('19', '7', 'reverse_charge')"
        }

      add :net, :integer, null: false
      add :vat_amount, :integer, null: false
      add :total, :integer, null: false
      add :positions, :map, null: false
      add :sender, :map, null: false
      add :recipient, :map, null: false

      timestamps()
    end

    create unique_index(:bookkeeping_invoices, [:user_id, :number])
    create index(:bookkeeping_invoices, [:customer_id])
  end
end
