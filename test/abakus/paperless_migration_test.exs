defmodule Abakus.PaperlessMigrationTest do
  use ExUnit.Case

  alias Abakus.{Repo, TestMigrations}

  @moduletag :tmp_dir
  @before 20_261_106_120_000
  @now "'2026-10-01T10:00:00.000000Z'"
  @polled "'2026-09-30T08:00:00.000000Z'"

  setup %{tmp_dir: dir} do
    repo = TestMigrations.start_repo!(dir)
    TestMigrations.run!(repo, to: @before)

    for {id, email} <- [{1, "anna"}, {2, "bert"}],
        do:
          Repo.query!(
            "INSERT INTO users (id, email, passkey_handle, budget_owner, inserted_at, updated_at) " <>
              "VALUES (#{id}, '#{email}@example.com', x'0#{id}', 0, #{@now}, #{@now})"
          )

    Repo.query!(
      "INSERT INTO depot_settings (user_id, paperless_url, paperless_token, paperless_tag, paperless_polled_at, " <>
        "inserted_at, updated_at) " <>
        "VALUES (1, 'http://paperless:8000', 'geheim', 'abakus', #{@polled}, #{@polled}, #{@now}), " <>
        "(2, NULL, NULL, NULL, NULL, #{@now}, #{@now})"
    )

    %{repo: repo}
  end

  test "moves URL and token to the user's connection and keeps the tag in the Depot", %{
    repo: repo
  } do
    TestMigrations.run!(repo)

    assert Repo.query!("SELECT user_id, url, token, updated_at FROM paperless_connections").rows ==
             [[1, "http://paperless:8000", "geheim", "2026-09-30T08:00:00.000000Z"]]

    assert Repo.query!("SELECT * FROM depot_settings ORDER BY user_id LIMIT 1").columns
           |> Enum.filter(&String.starts_with?(&1, "paperless")) ==
             ["paperless_tag", "paperless_polled_at"]

    assert Repo.query!("SELECT paperless_tag FROM depot_settings ORDER BY user_id").rows ==
             [["abakus"], [nil]]
  end
end
