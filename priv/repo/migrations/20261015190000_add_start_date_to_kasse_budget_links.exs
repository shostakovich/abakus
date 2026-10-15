defmodule Abakus.Repo.Migrations.AddStartDateToKasseBudgetLinks do
  use Ecto.Migration

  def change do
    alter table(:kasse_budget_links) do
      add :start_date, :date
    end
  end
end
