defmodule Abakus.Repo.Migrations.CreateCategories do
  use Ecto.Migration

  def change do
    create table(:category_groups) do
      add :name, :string, null: false
      add :hidden, :boolean, null: false, default: false
      add :internal, :boolean, null: false, default: false
      add :position, :integer, null: false, default: 0
      add :note, :text

      timestamps()
    end

    create table(:categories) do
      add :category_group_id, references(:category_groups, on_delete: :restrict), null: false
      add :name, :string, null: false
      add :lookup_key, :string, null: false
      add :hidden, :boolean, null: false, default: false
      add :internal, :boolean, null: false, default: false
      add :position, :integer, null: false, default: 0
      add :note, :text

      timestamps()
    end

    create index(:categories, [:category_group_id])
    create index(:categories, [:lookup_key])
  end
end
