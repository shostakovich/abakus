defmodule Abakus.Repo.Migrations.RecordDivvyDiaryUnknownIsins do
  use Ecto.Migration

  def change do
    alter table(:depot_securities) do
      add :divvy_diary_unknown, :boolean, null: false, default: false
    end
  end
end
