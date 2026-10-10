defmodule Abakus.Repo.Migrations.AddFileImport do
  use Ecto.Migration

  def change do
    alter table(:accounts) do
      add :ofx_bank_id, :string
      add :ofx_acct_id, :string
    end

    # A card account (CCACCTFROM) has no bank id.
    create unique_index(:accounts, [:ofx_acct_id, "coalesce(ofx_bank_id, '')"],
             name: :accounts_ofx_account_index,
             where: "ofx_acct_id IS NOT NULL"
           )

    create table(:bank_balances) do
      add :account_id, references(:accounts, on_delete: :restrict), null: false
      add :source, :string, null: false
      add :date, :date, null: false
      add :amount, :integer, null: false

      timestamps()
    end

    create unique_index(:bank_balances, [:account_id, :source, :date])
  end
end
