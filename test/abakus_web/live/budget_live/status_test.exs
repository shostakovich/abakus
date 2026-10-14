defmodule AbakusWeb.BudgetLive.StatusTest do
  use ExUnit.Case, async: true

  alias Abakus.Budget.{CategoryMonth, Month}
  alias AbakusWeb.BudgetLive.Status

  @oct ~D[2026-10-01]
  @nov ~D[2026-11-01]

  @monthly %{cadence: :monthly}
  @by_date %{cadence: :by_date}

  defp row(attrs), do: struct!(CategoryMonth, Enum.into(attrs, %{month: @oct}))

  describe "pill/1" do
    test "red when overspent, half when underfunded, a check for a met target, plain at zero" do
      assert Status.pill(row(available: -100, underfunded: 50)) ==
               %{tone: :error, icon: nil, label: "überzogen"}

      assert Status.pill(row(available: 100, underfunded: 50)) ==
               %{tone: :warning, icon: "circle-dashed", label: "unterfinanziert"}

      assert Status.pill(row(available: 100, target: @monthly)) ==
               %{tone: :success, icon: "circle-check", label: "Ziel erreicht"}

      assert Status.pill(row(available: 100)) == %{tone: :success, icon: nil, label: nil}
      assert Status.pill(row(available: 0)) == :zero
    end

    test "a snoozed target is neither underfunded nor met" do
      assert Status.pill(row(available: 100, underfunded: 50, snoozed: true, target: @monthly)) ==
               %{tone: :success, icon: nil, label: nil}
    end
  end

  describe "quiet/2" do
    test "red when negative, dimmed at zero, a dot while underfunded up to now or once assigned" do
      assert Status.quiet(row(available: -1), @oct) == %{tone: :error, dot: false}
      assert Status.quiet(row(available: 0), @oct) == %{tone: :muted, dot: false}
      assert Status.quiet(row(available: 5, underfunded: 5), @oct) == %{tone: nil, dot: true}
      assert Status.quiet(row(month: @nov, available: 5, underfunded: 5), @oct).dot == false
      assert Status.quiet(row(month: @nov, assigned: 1, underfunded: 5), @oct).dot == true
      assert Status.quiet(row(underfunded: 5, snoozed: true), @oct).dot == false
    end
  end

  describe "target_head/1" do
    test "a monthly target says what it sets aside or refills, without a day" do
      assert Status.target_head(%{cadence: :monthly, amount: 5_000, set_aside: true}) ==
               {"Jeden Monat weitere 50,00 € zurücklegen", nil}

      assert Status.target_head(%{cadence: :monthly, amount: 5_000, set_aside: false}) ==
               {"Jeden Monat auffüllen bis 50,00 €", nil}
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
               {"1.200,00 € bis 1. Juni 2027 ansparen",
                "Einmalig · weitere zurücklegen, verteilt auf die Monate bis dahin"}

      assert Status.target_head(%{once | repeats_yearly: true, set_aside: false}) ==
               {"1.200,00 € bis 1. Juni ansparen",
                "Jedes Jahr · auffüllen bis, verteilt auf die Monate bis dahin"}
    end
  end

  describe "target_status/1" do
    test "overspent wins, with the exact amount" do
      assert Status.target_status(row(target: @monthly, snoozed: true, available: -1_250)) ==
               %{title: "Überzogen 12,50 €", tone: :error}
    end

    test "nothing without a target, overspent or not" do
      assert Status.target_status(row(available: 500, activity: -100)) == nil
      assert Status.target_status(row(available: -1_250, activity: -1_250)) == nil
    end

    test "snoozed, underfunded, funded with what is spent" do
      assert %{title: "Pausiert", tone: :neutral} =
               Status.target_status(row(target: @monthly, snoozed: true, underfunded: 10))

      assert %{title: "Noch 50,00 € nötig", tone: :warning} =
               Status.target_status(row(target: @monthly, underfunded: 5_000))

      assert %{title: "Finanziert, 10,00 € von 10,00 € ausgegeben", tone: :success} =
               Status.target_status(row(target: @monthly, assigned: 1_000, activity: -1_000))

      assert %{title: "Finanziert, 29,99 € von 105,55 € ausgegeben", tone: :success} =
               Status.target_status(
                 row(
                   target: @monthly,
                   carried: 5_555,
                   assigned: 5_000,
                   activity: -2_999,
                   available: 7_556
                 )
               )

      assert %{title: "Finanziert", tone: :success} =
               Status.target_status(row(target: @monthly, assigned: 100, available: 100))

      assert %{title: "Im Plan"} = Status.target_status(row(target: @by_date, available: 100))
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
    test "red when too much is assigned, as it ended in a past month, green with money, else done" do
      assert Status.ready(%Month{ready_to_assign_shown: -1}) == {:error, "Zu viel verteilt"}

      assert Status.ready(%Month{ready_to_assign_shown: 5, closed: true}) ==
               {:muted, "Nicht verteilt am Monatsende"}

      assert Status.ready(%Month{ready_to_assign_shown: 5}) == {:success, "Zu verteilen"}
      assert Status.ready(%Month{ready_to_assign_shown: 0}) == {nil, "Alles verteilt"}
    end
  end

  describe "calculation/1" do
    test "explains Zu verteilen as Actual does: funds, last month's overspending, assigned, kept for later" do
      october = %Month{
        month: @oct,
        not_assigned_last_month: 52_126,
        overspent_last_month: 1_810,
        income: 324_000,
        assigned: 313_071,
        assigned_in_future: 39_200
      }

      assert Status.calculation(october) == [
               %{label: "Verfügbare Mittel", value: 376_126, tone: nil},
               %{label: "Überzogen im Sep", value: -1_810, tone: :error},
               %{label: "Zugewiesen", value: -313_071, tone: nil},
               %{label: "Für spätere Monate", value: -39_200, tone: nil}
             ]
    end

    test "a past month counts nothing for later months, as it shows Zu verteilen as it ended" do
      november = %Month{
        month: @nov,
        not_assigned_last_month: -500,
        assigned_in_future: 1_000,
        closed: true
      }

      assert [
               %{label: "Verfügbare Mittel", value: -500, tone: :error},
               %{label: "Überzogen im Okt", value: 0, tone: nil},
               %{label: "Zugewiesen", value: 0}
             ] = Status.calculation(november)
    end
  end

  test "uncovered/1 says which later months are short and by how much, with the year when it differs" do
    month = %Month{month: @oct, uncovered: [{@nov, 30_000}, {~D[2027-01-01], 5}]}

    assert Status.uncovered(month) == [
             "November nicht gedeckt: es fehlen 300,00 €",
             "Januar 2027 nicht gedeckt: es fehlen 0,05 €"
           ]
  end
end
