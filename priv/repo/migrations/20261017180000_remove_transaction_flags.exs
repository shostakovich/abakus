defmodule Abakus.Repo.Migrations.RemoveTransactionFlags do
  use Ecto.Migration

  def change do
    alter table(:transactions) do
      remove :flag, :string
    end
  end
end
