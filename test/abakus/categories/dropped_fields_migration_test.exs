defmodule Abakus.Categories.DroppedFieldsMigrationTest do
  use ExUnit.Case

  alias Abakus.{Repo, TestMigrations}

  @moduletag :tmp_dir
  @before 20_261_105_130_000
  @drop 20_261_105_140_000

  @fields [
    {"categories", "hidden"},
    {"categories", "note"},
    {"categories", "name"},
    {"category_groups", "hidden"},
    {"category_groups", "note"},
    {"accounts", "note"},
    {"accounts", "name"},
    {"payees", "hidden"}
  ]
  @row "01a0f5c0-0000-7000-8000-000000000001"
  @clock "2026-11-01T08:00:00.000Z-0000-server"

  setup %{tmp_dir: dir} do
    repo = TestMigrations.start_repo!(dir)
    TestMigrations.run!(repo, to: @before)
    now = "'2026-11-01T08:00:00.000000Z'"

    Repo.query!("""
    INSERT INTO users (id, email, passkey_handle, inserted_at, updated_at, budget_owner)
    VALUES (1, 'owner@example.com', x'01', #{now}, #{now}, 1)
    """)

    for {table, column} <- @fields do
      Repo.query!(
        ~s|INSERT INTO sync_field_clocks ("table", row_id, "column", clock) VALUES (?, ?, ?, ?)|,
        [table, @row, column, @clock]
      )

      Repo.query!(
        """
        INSERT INTO sync_messages (user_id, "table", row_id, "column", value, clock, device, inserted_at)
        VALUES (1, ?, ?, ?, '"Alter Text"', ?, 'server', #{now})
        """,
        [table, @row, column, @clock]
      )
    end

    %{repo: repo}
  end

  defp fields(sync_table),
    do: Repo.query!(~s|SELECT "table", "column" FROM #{sync_table} ORDER BY 1, 2|).rows

  defp columns(table),
    do: Repo.query!("SELECT name FROM pragma_table_info(?)", [table]).rows |> List.flatten()

  test "drops the notes and hidden flags of categories, groups and accounts with their sync state",
       %{repo: repo} do
    TestMigrations.run!(repo, to: @drop)

    for table <- ~w(categories category_groups),
        do: refute(Enum.any?(~w(hidden note), &(&1 in columns(table))))

    refute "note" in columns("accounts")
    assert "hidden" in columns("payees")

    kept = [["accounts", "name"], ["categories", "name"], ["payees", "hidden"]]
    assert fields("sync_field_clocks") == kept
    assert fields("sync_messages") == kept
  end
end
