defmodule Abakus.Repo.Migrations.RecordDivvyDiaryErrors do
  use Ecto.Migration

  def change do
    alter table(:depot_securities) do
      add :divvy_diary_error, :string
    end
  end
end
