defmodule AbakusWeb.BudgetLive.StatusTest do
  use ExUnit.Case, async: true

  alias Abakus.Budget.{CategoryMonth, Month}
  alias AbakusWeb.BudgetLive.Status

  @oct ~D[2026-10-01]
  @nov ~D[2026-11-01]

  @monthly %{cadence: :monthly}

  defp row(attrs), do: struct!(CategoryMonth, Enum.into(attrs, %{month: @oct}))

  describe "available/2" do
    test "red when overspent, amber with a ring while underfunded, a check for a funded target" do
      assert Status.available(row(available: -100, underfunded: 50, target: @monthly), true) ==
               %{tone: :error, icon: nil, ring: nil, label: "überzogen"}

      assert Status.available(
               row(available: 100, needed: 200, underfunded: 50, target: @monthly),
               true
             ) ==
               %{
                 tone: :warning,
                 icon: nil,
                 ring: 75,
                 label: "unterfinanziert, 75\u00A0% finanziert"
               }

      assert Status.available(row(available: 100, target: @monthly), true) ==
               %{tone: nil, icon: "circle-check", ring: nil, label: "Ziel erreicht"}
    end

    test "a refill target short of its amount after money was taken out has no share, so no ring" do
      assert Status.available(
               row(available: 4_000, needed: 0, underfunded: 1_000, target: @monthly),
               true
             ) ==
               %{tone: :warning, icon: nil, ring: nil, label: "unterfinanziert"}
    end

    test "a snoozed target pauses, neither underfunded nor funded" do
      assert Status.available(
               row(available: 100, needed: 200, underfunded: 50, snoozed: true, target: @monthly),
               true
             ) ==
               %{tone: nil, icon: "pause", ring: nil, label: "Ziel pausiert"}

      assert Status.available(row(snoozed: true, target: @monthly), true).tone == :muted
    end

    test "plain without a target, muted at zero" do
      assert Status.available(row(available: 100), true) ==
               %{tone: nil, icon: nil, ring: nil, label: nil}

      assert Status.available(row(available: 0), true) ==
               %{tone: :muted, icon: nil, ring: nil, label: nil}
    end

    test "an underfunded target stays plain in a month not being budgeted; the other states show" do
      assert Status.available(
               row(available: 100, needed: 200, underfunded: 50, target: @monthly),
               false
             ) ==
               %{tone: nil, icon: nil, ring: nil, label: nil}

      assert Status.available(row(available: -100, underfunded: 50, target: @monthly), false).tone ==
               :error

      assert Status.available(row(available: 100, target: @monthly), false).icon == "circle-check"

      assert Status.available(row(underfunded: 50, snoozed: true, target: @monthly), false).icon ==
               "pause"
    end
  end

  describe "funded_share/1" do
    test "a monthly target: what of the month's need is assigned, in whole percent rounded down" do
      assert Status.funded_share(row(target: @monthly, needed: 4_000, underfunded: 1_500)) == 62
      assert Status.funded_share(row(target: @monthly, needed: 4_000, underfunded: 4_000)) == 0
      assert Status.funded_share(row(target: @monthly, needed: 4_000, underfunded: 1)) == 99
    end

    test "a target by a date: what of this month's share of the amount is assigned" do
      by_date = %{cadence: :by_date, amount: 20_000}

      assert Status.funded_share(
               row(target: by_date, needed: 13_334, underfunded: 5_334, saved: 8_000)
             ) == 59
    end

    test "nothing while the target is snoozed or asks nothing more" do
      refute Status.funded_share(
               row(target: @monthly, needed: 4_000, underfunded: 1_500, snoozed: true)
             )

      refute Status.funded_share(row(target: @monthly, needed: 4_000, underfunded: 0))
      refute Status.funded_share(row(needed: 0, underfunded: 0))
    end
  end

  test "budgeting?/2: the current month, and any other with money assigned" do
    assert Status.budgeting?(%Month{month: @oct}, @oct)
    refute Status.budgeting?(%Month{month: @nov}, @oct)
    assert Status.budgeting?(%Month{month: @nov, assigned: 1}, @oct)
    assert Status.budgeting?(%Month{month: ~D[2026-09-01], assigned: -5}, @oct)
  end

  describe "target_head/1" do
    test "a monthly target in one sentence, setting aside or refilling" do
      assert Status.target_head(%{cadence: :monthly, amount: 5_000, set_aside: true}) ==
               "Jeden Monat weitere 50,00 € zurücklegen"

      assert Status.target_head(%{cadence: :monthly, amount: 65_000, set_aside: false}) ==
               "Jeden Monat auffüllen bis 650,00 €"
    end

    test "a target by a date names its date, a repeating one without the year" do
      once = %{
        cadence: :by_date,
        amount: 120_000,
        due_on: ~D[2027-06-01],
        repeats_yearly: false,
        set_aside: true
      }

      assert Status.target_head(once) ==
               "Bis zum 1. Juni 2027 weitere 1.200,00 € zurücklegen"

      assert Status.target_head(%{once | repeats_yearly: true, set_aside: false}) ==
               "Jedes Jahr bis zum 1. Juni auf 1.200,00 € ansparen"
    end
  end

  describe "target_status/1" do
    test "nothing without a target, overspent or not" do
      assert Status.target_status(row(available: 500, activity: -100)) == nil
      assert Status.target_status(row(available: -1_250, activity: -1_250)) == nil
    end

    test "one sentence: overspent wins over snoozed, then paused, still missing, funded" do
      assert Status.target_status(row(target: @monthly, snoozed: true, available: -18_020)) ==
               %{text: "Überzogen um 180,20 €.", tone: :error, icon: nil}

      assert Status.target_status(row(target: @monthly, snoozed: true, underfunded: 10)) ==
               %{text: "Pausiert im Oktober.", tone: :muted, icon: "pause"}

      assert Status.target_status(row(target: @monthly, underfunded: 6_834)) ==
               %{text: "Noch 68,34 € diesen Monat.", tone: :warning, icon: "clock"}

      assert %{text: "Erfüllt.", tone: :success} =
               Status.target_status(row(target: @monthly, assigned: 1_000, activity: -1_000))
    end

    test "a target by a date is on track until its amount is saved" do
      by_date = %{cadence: :by_date, amount: 120_000}

      assert %{text: "Im Plan."} =
               Status.target_status(row(target: by_date, saved: 8_000, available: 8_000))

      assert %{text: "Erfüllt."} =
               Status.target_status(row(target: by_date, saved: 120_000, available: 120_000))
    end
  end

  describe "target_mark/1" do
    test "a target by a date marks where it should stand after this month, others none" do
      by_date = %{cadence: :by_date, amount: 120_000}

      assert Status.target_mark(row(target: by_date, saved: 8_000, underfunded: 5_334)) == 11
      assert Status.target_mark(row(target: by_date, saved: 8_000, snoozed: true)) == 7
      assert Status.target_mark(row(target: %{cadence: :monthly, amount: 5_000})) == nil
    end
  end

  describe "ready/1" do
    test "an open month says Zu verteilen in the colour of its sign, a past month how it ended" do
      assert Status.ready(%Month{ready_to_assign_shown: 5}) == {:success, "Zu verteilen"}
      assert Status.ready(%Month{ready_to_assign_shown: -1}) == {:error, "Zu verteilen"}
      assert Status.ready(%Month{ready_to_assign_shown: 0}) == {nil, "Zu verteilen"}

      assert Status.ready(%Month{ready_to_assign_shown: 5, closed: true}) ==
               {:muted, "Nicht verteilt am Monatsende"}

      assert Status.ready(%Month{ready_to_assign_shown: -1, closed: true}) ==
               {:error, "Zu viel verteilt"}
    end
  end

  describe "calculation/1" do
    test "explains Zu verteilen as YNAB 4 does, the lines adding up to it" do
      october = %Month{
        month: @oct,
        not_assigned_last_month: 52_126,
        overspent_last_month: 1_810,
        income: 324_000,
        assigned: 313_071,
        assigned_in_future: 39_200,
        ready_to_assign_shown: 22_045
      }

      lines = Status.calculation(october)

      assert lines == [
               %{label: "Nicht verteilt im Sep", value: 52_126, tone: nil},
               %{label: "Überzogen im Sep", value: -1_810, tone: :error},
               %{label: "Einnahmen im Okt", value: 324_000, tone: nil},
               %{label: "Zugewiesen im Okt", value: -313_071, tone: nil},
               %{label: "Für spätere Monate", value: -39_200, tone: nil}
             ]

      assert lines |> Enum.map(& &1.value) |> Enum.sum() == october.ready_to_assign_shown
    end

    test "leaves out later months when they assigned nothing, and in a past month, which ended without them" do
      assert [_, _, _, _] = Status.calculation(%Month{month: @nov})

      november = %Month{
        month: @nov,
        not_assigned_last_month: -500,
        assigned_in_future: 1_000,
        closed: true
      }

      assert [
               %{label: "Nicht verteilt im Okt", value: -500, tone: :error},
               %{label: "Überzogen im Okt", value: 0, tone: nil},
               %{label: "Einnahmen im Nov", value: 0},
               %{label: "Zugewiesen im Nov", value: 0}
             ] = Status.calculation(november)
    end
  end

  test "uncovered/1 lists the later months that are short as lines of the calculation, with the year when it differs" do
    month = %Month{month: @oct, uncovered: [{@nov, 30_000}, {~D[2027-01-01], 5}]}

    assert Status.uncovered(month) == [
             %{label: "Nicht gedeckt im Nov", value: -30_000, tone: :error},
             %{label: "Nicht gedeckt im Jan 2027", value: -5, tone: :error}
           ]
  end
end
