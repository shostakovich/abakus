defmodule Abakus.Repo.Migrations.CreatePayees do
  use Ecto.Migration

  def change do
    create table(:payees) do
      add :name, :string, null: false
      add :lookup_key, :string, null: false
      add :transfer_account_id, references(:accounts, on_delete: :restrict)
      add :last_category_id, references(:categories, on_delete: :restrict)

      timestamps()
    end

    create unique_index(:payees, [:transfer_account_id])
    create unique_index(:payees, [:lookup_key], where: "transfer_account_id IS NULL")
    create index(:payees, [:last_category_id])
  end
end
