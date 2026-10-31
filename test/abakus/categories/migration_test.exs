defmodule Abakus.Categories.MigrationTest do
  use ExUnit.Case

  alias Abakus.{Repo, TestMigrations}

  @moduletag :tmp_dir
  @before_uuids 20_261_021_220_000
  @before 20_261_017_140_000
  @tables ~w(category_groups categories assignments target_versions target_snoozes)
  @now "'2026-10-01T10:00:00.000000Z'"

  setup %{tmp_dir: dir} do
    repo = TestMigrations.start_repo!(dir)
    TestMigrations.run!(repo, to: @before)
    %{repo: repo}
  end

  defp insert_users do
    Repo.query!("""
    INSERT INTO users (id, email, passkey_handle, inserted_at, updated_at, budget_owner)
    VALUES (1, 'kasse@example.com', x'01', #{@now}, #{@now}, 0),
           (2, 'owner@example.com', x'02', #{@now}, #{@now}, 1)
    """)
  end

  defp insert_budget do
    Repo.query!("""
    INSERT INTO category_groups (id, name, inserted_at, updated_at) VALUES (5, 'Alltag', #{@now}, #{@now})
    """)

    Repo.query!("""
    INSERT INTO categories (id, category_group_id, name, lookup_key, inserted_at, updated_at)
    VALUES (7, 5, 'Lebensmittel', 'lebensmittel', #{@now}, #{@now}),
           (9, 5, 'Weg', 'weg', #{@now}, #{@now})
    """)

    Repo.query!("DELETE FROM categories WHERE id = 9")

    Repo.query!("""
    INSERT INTO assignments (category_id, month, amount, inserted_at, updated_at)
    VALUES (7, '2026-10-01', 5000, #{@now}, #{@now})
    """)

    Repo.query!("""
    INSERT INTO target_versions (category_id, from_month, cadence, amount, inserted_at, updated_at)
    VALUES (7, '2026-10-01', 'monthly', 5000, #{@now}, #{@now})
    """)

    Repo.query!("""
    INSERT INTO target_snoozes (category_id, month, inserted_at, updated_at)
    VALUES (7, '2026-10-01', #{@now}, #{@now})
    """)

    Repo.query!("""
    INSERT INTO accounts (id, user_id, name, kind, inserted_at, updated_at)
    VALUES (1, 2, 'Giro', 'checking', #{@now}, #{@now})
    """)

    Repo.query!("""
    INSERT INTO transactions (id, user_id, account_id, date, amount, category_id, inserted_at, updated_at)
    VALUES (1, 2, 1, '2026-10-01', -5000, 7, #{@now}, #{@now})
    """)
  end

  test "gives every row of the categories to the budget owner and keeps the rest", %{repo: repo} do
    insert_users()
    insert_budget()
    TestMigrations.run!(repo, to: @before_uuids)

    for table <- @tables do
      assert Repo.query!(~s|SELECT DISTINCT user_id FROM "#{table}"|).rows == [[2]], table
    end

    assert Repo.query!("SELECT id FROM categories WHERE NOT internal").rows == [[7]]
    assert Repo.query!("SELECT count(*) FROM categories WHERE internal").rows == [[1]]
    assert Repo.query!("SELECT category_id FROM transactions").rows == [[7]]

    assert Repo.query!("SELECT seq FROM sqlite_sequence WHERE name = 'categories'").rows == [
             [9]
           ]

    assert Repo.query!("PRAGMA foreign_keys").rows == [[1]]
  end

  test "without an owner drops the internal rows, which come with each user's first use",
       %{repo: repo} do
    TestMigrations.run!(repo, to: @before_uuids)

    assert Repo.query!("SELECT count(*) FROM categories").rows == [[0]]
    assert Repo.query!("SELECT count(*) FROM category_groups").rows == [[0]]
  end

  test "refuses rows of the categories without a budget owner", %{repo: repo} do
    insert_users()
    insert_budget()
    Repo.query!("UPDATE users SET budget_owner = 0")

    assert_raise RuntimeError, ~r/No user owns the budget.*category_groups, categories/, fn ->
      TestMigrations.run!(repo, to: @before_uuids)
    end

    refute ["user_id"] in Repo.query!("SELECT name FROM pragma_table_info('categories')").rows
  end

  test "requires an owner for every new row and one internal group per user", %{repo: repo} do
    insert_users()
    TestMigrations.run!(repo, to: @before_uuids)

    assert_raise Exqlite.Error, ~r/NOT NULL constraint failed: category_groups.user_id/, fn ->
      Repo.query!("""
      INSERT INTO category_groups (name, inserted_at, updated_at) VALUES ('X', #{@now}, #{@now})
      """)
    end

    assert_raise Exqlite.Error, ~r/UNIQUE constraint failed/, fn ->
      Repo.query!("""
      INSERT INTO category_groups (user_id, name, internal, inserted_at, updated_at)
      VALUES (2, 'X', 1, #{@now}, #{@now})
      """)
    end
  end
end
