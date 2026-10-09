defmodule Abakus.Repo.Migrations.CreateAccounts do
  use Ecto.Migration

  def change do
    create table(:accounts) do
      add :name, :string, null: false
      add :kind, :string, null: false
      add :fed_by, :string
      add :closed, :boolean, null: false, default: false
      add :note, :text
      add :position, :integer, null: false, default: 0
      add :last_reconciled_at, :utc_datetime_usec

      timestamps()
    end
  end
end
