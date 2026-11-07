defmodule Abakus.Repo.Migrations.CreateBookkeepingFixedAssets do
  use Ecto.Migration

  def change do
    create table(:bookkeeping_fixed_assets, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :purchased_on, :date, null: false
      add :net, :integer, null: false
      add :useful_life, :integer

      timestamps()
    end

    create index(:bookkeeping_fixed_assets, [:user_id])

    create table(:bookkeeping_disposals, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :user_id, references(:users, on_delete: :delete_all), null: false

      add :fixed_asset_id,
          references(:bookkeeping_fixed_assets, type: :uuid, on_delete: :delete_all),
          null: false

      add :kind, :string,
        null: false,
        check: %{name: "bookkeeping_disposals_kind_check", expr: "kind IN ('sale', 'withdrawal')"}

      add :date, :date, null: false
      add :amount, :integer, null: false

      add :vat, :string,
        null: false,
        check: %{
          name: "bookkeeping_disposals_vat_check",
          expr: "vat IN ('19', '16', '7', '5', '0')"
        }

      add :transaction_id, references(:transactions, type: :uuid, on_delete: :nilify_all)

      timestamps()
    end

    create unique_index(:bookkeeping_disposals, [:fixed_asset_id])
    create unique_index(:bookkeeping_disposals, [:transaction_id])
    create index(:bookkeeping_disposals, [:user_id])
  end
end
