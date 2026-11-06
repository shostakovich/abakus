defmodule Abakus.Repo.Migrations.RepeatScheduledTransactions do
  use Ecto.Migration

  @repeats [
    once: {nil, nil},
    weekly: {"week", 1},
    daily: {"week", 1},
    every_other_week: {"week", 2},
    every_4_weeks: {"week", 4},
    monthly: {"month", 1},
    twice_a_month: {"month", 1},
    every_other_month: {"month", 2},
    every_3_months: {"month", 3},
    every_4_months: {"month", 4},
    twice_a_year: {"month", 6},
    yearly: {"month", 12},
    every_other_year: {"month", 24}
  ]

  @dropped ~w(frequency first_day second_day)

  def change do
    alter table(:scheduled_transactions) do
      add :repeat_unit, :string,
        check: %{
          name: "scheduled_transactions_repeat_unit_check",
          expr: "repeat_unit IN ('week', 'month')"
        }

      add :repeat_every, :integer,
        check: %{
          name: "scheduled_transactions_repeat_every_check",
          expr: "repeat_every BETWEEN 1 AND 99"
        }
    end

    execute(&repeat_frequencies/0, &frequency_repeats/0)

    alter table(:scheduled_transactions) do
      remove :frequency, :string, null: false, default: "once"
      remove :first_day, :integer
      remove :second_day, :integer
    end

    execute(&forget_sync_state/0, fn -> :ok end)
  end

  defp repeat_frequencies do
    for {frequency, {unit, every}} <- @repeats,
        do:
          query!(
            "UPDATE scheduled_transactions SET repeat_unit = ?, repeat_every = ? WHERE frequency = ?",
            [unit, every, Atom.to_string(frequency)]
          )
  end

  defp frequency_repeats do
    query!("""
    UPDATE scheduled_transactions SET frequency = iif(repeat_unit = 'week', 'weekly', 'monthly')
    WHERE repeat_unit IS NOT NULL
    """)

    for {frequency, {unit, every}} <- Enum.uniq_by(@repeats, &elem(&1, 1)),
        unit,
        do:
          query!(
            "UPDATE scheduled_transactions SET frequency = ? WHERE repeat_unit = ? AND repeat_every = ?",
            [Atom.to_string(frequency), unit, every]
          )
  end

  defp forget_sync_state do
    for column <- @dropped,
        sync_table <- ~w(sync_field_clocks sync_messages),
        do:
          query!(
            ~s|DELETE FROM #{sync_table} WHERE "table" = 'scheduled_transactions' AND "column" = ?|,
            [column]
          )
  end

  defp query!(sql, params \\ []), do: repo().query!(sql, params, log: false)
end
