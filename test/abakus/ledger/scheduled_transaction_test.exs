defmodule Abakus.Ledger.ScheduledTransactionTest do
  use ExUnit.Case, async: true

  alias Abakus.Ledger.ScheduledTransaction

  defp following(frequency, date, days \\ {nil, nil}) do
    {first_day, second_day} = days

    ScheduledTransaction.following(%ScheduledTransaction{
      frequency: frequency,
      next_date: date,
      first_day: first_day,
      second_day: second_day
    })
  end

  test "steps by days, months and years, a day the month lacks being its last" do
    assert following(:daily, ~D[2026-12-31]) == ~D[2027-01-01]
    assert following(:weekly, ~D[2026-12-28]) == ~D[2027-01-04]
    assert following(:every_other_week, ~D[2026-12-28]) == ~D[2027-01-11]
    assert following(:every_4_weeks, ~D[2026-12-28]) == ~D[2027-01-25]
    assert following(:monthly, ~D[2027-01-31]) == ~D[2027-02-28]
    assert following(:monthly, ~D[2027-02-28]) == ~D[2027-03-28]
    assert following(:every_other_month, ~D[2026-12-31]) == ~D[2027-02-28]
    assert following(:every_3_months, ~D[2026-11-30]) == ~D[2027-02-28]
    assert following(:every_4_months, ~D[2026-10-31]) == ~D[2027-02-28]
    assert following(:twice_a_year, ~D[2026-08-31]) == ~D[2027-02-28]
    assert following(:yearly, ~D[2028-02-29]) == ~D[2029-02-28]
    assert following(:every_other_year, ~D[2026-12-01]) == ~D[2028-12-01]
    assert following(:once, ~D[2026-12-01]) == nil
  end

  test "twice a month falls on its two days, a day the month lacks being its last" do
    assert following(:twice_a_month, ~D[2027-01-15], {15, 31}) == ~D[2027-01-31]
    assert following(:twice_a_month, ~D[2027-01-31], {15, 31}) == ~D[2027-02-15]
    assert following(:twice_a_month, ~D[2027-02-15], {15, 31}) == ~D[2027-02-28]
    assert following(:twice_a_month, ~D[2027-02-28], {15, 31}) == ~D[2027-03-15]
    assert following(:twice_a_month, ~D[2027-01-10], {1, 15}) == ~D[2027-01-15]
    assert following(:twice_a_month, ~D[2027-01-20], {1, 15}) == ~D[2027-02-01]
  end

  test "twice a month takes its days in either order, and without two days is monthly" do
    assert following(:twice_a_month, ~D[2027-01-10], {15, 1}) == ~D[2027-01-15]
    assert following(:twice_a_month, ~D[2027-01-20], {15, 1}) == ~D[2027-02-01]
    assert following(:twice_a_month, ~D[2027-01-31], {nil, nil}) == ~D[2027-02-28]
    assert following(:twice_a_month, ~D[2027-01-10], {15, nil}) == ~D[2027-02-10]
    assert following(:twice_a_month, ~D[2027-01-10], {15, 15}) == ~D[2027-02-10]
    assert following(:twice_a_month, ~D[2027-01-10], {0, 40}) == ~D[2027-02-10]
  end

  test "twice a month needs two days in order" do
    changeset = fn days ->
      ScheduledTransaction.changeset(
        %ScheduledTransaction{user_id: 1},
        Map.merge(
          %{account_id: Ecto.UUID.generate(), next_date: ~D[2026-12-01], amount: -100},
          days
        )
      )
    end

    assert changeset.(%{frequency: :twice_a_month, first_day: 1, second_day: 15}).valid?
    refute changeset.(%{frequency: :twice_a_month, first_day: 15, second_day: 1}).valid?
    refute changeset.(%{frequency: :twice_a_month, first_day: 1}).valid?
    refute changeset.(%{frequency: :twice_a_month, first_day: 0, second_day: 15}).valid?

    assert %{changes: changes} = changeset.(%{frequency: :monthly, first_day: 1, second_day: 15})
    refute Map.has_key?(changes, :first_day)
  end
end
