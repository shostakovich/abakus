defmodule Abakus.Repo.Migrations.CreateTargets do
  use Ecto.Migration

  def change do
    create table(:target_versions) do
      add :category_id, references(:categories, on_delete: :restrict), null: false
      add :from_month, :date, null: false
      add :cadence, :string, null: false
      add :amount, :integer, check: %{name: "target_versions_amount_positive", expr: "amount > 0"}
      add :due_on, :date
      add :set_aside, :boolean, null: false, default: true

      timestamps()
    end

    create unique_index(:target_versions, [:category_id, :from_month])

    create table(:target_snoozes) do
      add :category_id, references(:categories, on_delete: :restrict), null: false
      add :month, :date, null: false

      timestamps()
    end

    create unique_index(:target_snoozes, [:category_id, :month])
  end
end
