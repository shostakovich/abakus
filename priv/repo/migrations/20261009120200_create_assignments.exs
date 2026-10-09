defmodule Abakus.Repo.Migrations.CreateAssignments do
  use Ecto.Migration

  def change do
    create table(:assignments) do
      add :category_id, references(:categories, on_delete: :restrict), null: false
      add :month, :date, null: false
      add :amount, :integer, null: false

      timestamps()
    end

    create unique_index(:assignments, [:category_id, :month])
  end
end
