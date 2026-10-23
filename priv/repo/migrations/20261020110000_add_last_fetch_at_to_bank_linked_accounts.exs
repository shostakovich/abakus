defmodule Abakus.Repo.Migrations.AddLastFetchAtToBankLinkedAccounts do
  use Ecto.Migration

  def change do
    alter table(:bank_linked_accounts) do
      add :last_fetch_at, :utc_datetime_usec
    end
  end
end
