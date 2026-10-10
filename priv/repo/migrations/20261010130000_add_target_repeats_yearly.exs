defmodule Abakus.Repo.Migrations.AddTargetRepeatsYearly do
  use Ecto.Migration

  def up do
    alter table(:target_versions) do
      add :repeats_yearly, :boolean, null: false, default: false
    end

    execute "UPDATE target_versions SET cadence = 'by_date', repeats_yearly = 1 WHERE cadence = 'yearly'"
  end

  def down do
    execute "UPDATE target_versions SET cadence = 'yearly' WHERE cadence = 'by_date'"

    alter table(:target_versions) do
      remove :repeats_yearly
    end
  end
end
