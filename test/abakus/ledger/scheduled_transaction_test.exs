defmodule Abakus.Ledger.ScheduledTransactionTest do
  use ExUnit.Case, async: true

  alias Abakus.Ledger.ScheduledTransaction

  defp scheduled(date, unit, every),
    do: %ScheduledTransaction{next_date: date, repeat_unit: unit, repeat_every: every}

  defp following(date, unit, every),
    do: ScheduledTransaction.following(scheduled(date, unit, every))

  test "steps n weeks by 7 × n days" do
    assert following(~D[2026-12-28], :week, 1) == ~D[2027-01-04]
    assert following(~D[2026-12-09], :week, 2) == ~D[2026-12-23]
    assert following(~D[2026-12-28], :week, 4) == ~D[2027-01-25]
  end

  test "steps n months to the same day, or the month's last day if it is shorter" do
    assert following(~D[2027-01-31], :month, 1) == ~D[2027-02-28]
    assert following(~D[2027-02-28], :month, 1) == ~D[2027-03-28]
    assert following(~D[2026-12-31], :month, 2) == ~D[2027-02-28]
    assert following(~D[2026-08-31], :month, 6) == ~D[2027-02-28]
    assert following(~D[2028-02-29], :month, 12) == ~D[2029-02-28]
    assert following(~D[2026-12-01], :month, 24) == ~D[2028-12-01]
  end

  test "happens once without a unit, and steps by 1 with a unit but no count" do
    assert following(~D[2026-12-01], nil, nil) == nil
    assert following(~D[2026-12-01], nil, 3) == nil
    assert following(~D[2026-12-09], :week, nil) == ~D[2026-12-16]
  end

  test "the dates after the next date" do
    assert ScheduledTransaction.dates_after(scheduled(~D[2026-12-09], :week, 2), 3) ==
             [~D[2026-12-23], ~D[2027-01-06], ~D[2027-01-20]]

    assert ScheduledTransaction.dates_after(scheduled(~D[2027-01-31], :month, 1), 2) ==
             [~D[2027-02-28], ~D[2027-03-28]]

    assert ScheduledTransaction.dates_after(scheduled(~D[2026-12-01], nil, nil), 3) == []
  end

  test "labels the repeat" do
    label = &ScheduledTransaction.repeat_label(scheduled(~D[2026-12-01], &1, &2))

    assert label.(nil, nil) == "Einmalig"
    assert label.(:week, 1) == "Wöchentlich"
    assert label.(:week, 2) == "Alle 2 Wochen"
    assert label.(:month, 1) == "Monatlich"
    assert label.(:month, 12) == "Jährlich"
    assert label.(:month, 3) == "Alle 3 Monate"
    assert label.(:week, nil) == "Wöchentlich"
  end

  describe "changeset" do
    defp changeset(repeat) do
      ScheduledTransaction.changeset(
        %ScheduledTransaction{user_id: 1},
        Map.merge(
          %{account_id: Ecto.UUID.generate(), next_date: ~D[2026-12-01], amount: -100},
          repeat
        )
      )
    end

    test "takes a unit with a count from 1 to 99" do
      assert changeset(%{repeat_unit: :week, repeat_every: 2}).valid?
      assert changeset(%{repeat_unit: :month, repeat_every: 99}).valid?
      refute changeset(%{repeat_unit: :month, repeat_every: 0}).valid?
      refute changeset(%{repeat_unit: :month, repeat_every: 100}).valid?
      refute changeset(%{repeat_unit: :month}).valid?
      refute changeset(%{repeat_unit: :day, repeat_every: 1}).valid?
    end

    test "once has neither unit nor count" do
      changeset = changeset(%{repeat_every: 3})

      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :repeat_every) == nil
    end
  end
end
