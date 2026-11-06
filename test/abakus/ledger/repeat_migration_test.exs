defmodule Abakus.Ledger.RepeatMigrationTest do
  use ExUnit.Case

  alias Abakus.{Repo, TestMigrations}

  @moduletag :tmp_dir
  @before 20_261_105_140_000
  @now "'2026-11-01T10:00:00.000000Z'"
  @account "01a0f5c0-0000-7000-8000-000000000001"

  @repeats [
    once: [nil, nil],
    daily: ["week", 1],
    weekly: ["week", 1],
    every_other_week: ["week", 2],
    every_4_weeks: ["week", 4],
    twice_a_month: ["month", 1],
    monthly: ["month", 1],
    every_other_month: ["month", 2],
    every_3_months: ["month", 3],
    every_4_months: ["month", 4],
    twice_a_year: ["month", 6],
    yearly: ["month", 12],
    every_other_year: ["month", 24]
  ]

  setup %{tmp_dir: dir} do
    repo = TestMigrations.start_repo!(dir)
    TestMigrations.run!(repo, to: @before)

    sql!("""
    INSERT INTO users (id, email, passkey_handle, inserted_at, updated_at, budget_owner)
    VALUES (1, 'owner@example.com', x'01', #{@now}, #{@now}, 1)
    """)

    sql!(
      "INSERT INTO accounts (id, user_id, name, kind, inserted_at, updated_at) VALUES (?, 1, 'Giro', 'checking', #{@now}, #{@now})",
      [@account]
    )

    %{repo: repo}
  end

  test "maps every frequency to a unit and a count, and drops the old columns", %{repo: repo} do
    for {{frequency, _repeat}, index} <- Enum.with_index(@repeats) do
      days = if frequency == :twice_a_month, do: [1, 15], else: [nil, nil]

      sql!(
        """
        INSERT INTO scheduled_transactions (id, user_id, account_id, next_date, frequency, first_day, second_day,
          amount, inserted_at, updated_at)
        VALUES (?, 1, ?, '2026-12-01', ?, ?, ?, -100, #{@now}, #{@now})
        """,
        [id(index), @account, Atom.to_string(frequency) | days]
      )
    end

    TestMigrations.run!(repo)

    assert sql!("SELECT repeat_unit, repeat_every FROM scheduled_transactions ORDER BY id").rows ==
             Keyword.values(@repeats)

    columns = sql!("SELECT name FROM pragma_table_info('scheduled_transactions')").rows

    for column <- ~w(frequency first_day second_day), do: refute([column] in columns)
  end

  test "keeps a count from 1 to 99 and only weeks and months", %{repo: repo} do
    TestMigrations.run!(repo)

    insert = fn unit, every ->
      sql!(
        """
        INSERT INTO scheduled_transactions (id, user_id, account_id, next_date, repeat_unit, repeat_every, amount,
          inserted_at, updated_at)
        VALUES (?, 1, ?, '2026-12-01', ?, ?, -100, #{@now}, #{@now})
        """,
        [Ecto.UUID.generate(), @account, unit, every]
      )
    end

    insert.("week", 99)
    insert.(nil, nil)
    assert_raise Exqlite.Error, fn -> insert.("month", 0) end
    assert_raise Exqlite.Error, fn -> insert.("month", 100) end
    assert_raise Exqlite.Error, fn -> insert.("day", 1) end
  end

  test "forgets the old columns' clocks and messages", %{repo: repo} do
    fields =
      [{"scheduled_transactions", "frequency"}, {"scheduled_transactions", "first_day"}] ++
        [{"scheduled_transactions", "second_day"}, {"scheduled_transactions", "amount"}]

    for {{table, column}, index} <- Enum.with_index(fields) do
      sql!(
        ~s|INSERT INTO sync_field_clocks ("table", row_id, "column", clock) VALUES (?, 'row', ?, ?)|,
        [
          table,
          column,
          "c#{index}"
        ]
      )

      sql!(
        """
        INSERT INTO sync_messages (user_id, "table", row_id, "column", value, clock, device, inserted_at)
        VALUES (1, ?, 'row', ?, '1', ?, 'mac', #{@now})
        """,
        [table, column, "c#{index}"]
      )
    end

    TestMigrations.run!(repo)

    for table <- ~w(sync_field_clocks sync_messages),
        do: assert(sql!(~s|SELECT "column" FROM #{table}|).rows == [["amount"]])
  end

  defp id(index),
    do: "01a0f5c0-0000-7000-8000-#{String.pad_leading(Integer.to_string(index + 10), 12, "0")}"

  defp sql!(sql, params \\ []), do: Repo.query!(sql, params)
end
