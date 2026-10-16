defmodule Abakus.Repo.Migrations.AddBudgetOwner do
  use Ecto.Migration

  def up do
    alter table(:users) do
      add :budget_owner, :boolean, null: false, default: false
    end

    create unique_index(:users, [:budget_owner], where: "budget_owner")

    # Until now every user saw the budget; the first one invited owns it.
    execute "UPDATE users SET budget_owner = 1 WHERE id = (SELECT min(id) FROM users)"
  end

  def down do
    drop index(:users, [:budget_owner])

    alter table(:users) do
      remove :budget_owner
    end
  end
end
