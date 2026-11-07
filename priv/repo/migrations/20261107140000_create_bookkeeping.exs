defmodule Abakus.Repo.Migrations.CreateBookkeeping do
  use Ecto.Migration

  def change do
    create table(:bookkeeping_business_accounts, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :account_id, references(:accounts, type: :uuid, on_delete: :delete_all), null: false

      timestamps()
    end

    create unique_index(:bookkeeping_business_accounts, [:account_id])
    create index(:bookkeeping_business_accounts, [:user_id])

    create table(:bookkeeping_tax_lines, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :user_id, references(:users, on_delete: :delete_all), null: false

      add :transaction_id, references(:transactions, type: :uuid, on_delete: :delete_all),
        null: false

      add :subtransaction_id,
          references(:subtransactions, type: :uuid, on_delete: :delete_all)

      add :category, :string, null: false

      add :vat, :string,
        null: false,
        check: %{
          name: "bookkeeping_tax_lines_vat_check",
          expr: "vat IN ('19', '16', '7', '5', '0', 'reverse_charge')"
        }

      timestamps()
    end

    create unique_index(:bookkeeping_tax_lines, [:transaction_id],
             where: "subtransaction_id IS NULL",
             name: :bookkeeping_tax_lines_transaction_index
           )

    create unique_index(:bookkeeping_tax_lines, [:subtransaction_id])
    create index(:bookkeeping_tax_lines, [:user_id])
  end
end
