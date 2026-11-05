defmodule Abakus.Repo.Migrations.DropRemovedBudgetFields do
  use Ecto.Migration

  @dropped [
    {"categories", ~w(hidden note)},
    {"category_groups", ~w(hidden note)},
    {"accounts", ~w(note)}
  ]

  def change do
    for table <- [:categories, :category_groups] do
      alter table(table) do
        remove :hidden, :boolean, null: false, default: false
        remove :note, :text
      end
    end

    alter table(:accounts) do
      remove :note, :text
    end

    execute(&forget_sync_state/0, fn -> :ok end)
  end

  defp forget_sync_state do
    for {table, columns} <- @dropped,
        column <- columns,
        sync_table <- ~w(sync_field_clocks sync_messages),
        do:
          repo().query!(
            ~s|DELETE FROM #{sync_table} WHERE "table" = ? AND "column" = ?|,
            [table, column],
            log: false
          )
  end
end
