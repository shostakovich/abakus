defmodule AbakusWeb.BudgetLive.StatusTest do
  use ExUnit.Case, async: true

  alias Abakus.Budget.{CategoryMonth, Month}
  alias AbakusWeb.BudgetLive.Status

  @oct ~D[2026-10-01]
  @nov ~D[2026-11-01]

  @monthly %{cadence: :monthly}
  @yearly %{cadence: :yearly}

  defp row(attrs), do: struct!(CategoryMonth, Enum.into(attrs, %{month: @oct}))

  describe "pill/1" do
    test "red when overspent, half when underfunded, a check for a met target, plain at zero" do
      assert Status.pill(row(available: -100, underfunded: 50)) == {"text-bg-danger", nil}
      assert Status.pill(row(available: 100, underfunded: 50)) == {"text-bg-warning", "half"}
      assert Status.pill(row(available: 100, target: @monthly)) == {"text-bg-success", "okc"}
      assert Status.pill(row(available: 100)) == {"text-bg-success", nil}
      assert Status.pill(row(available: 0)) == :zero
    end

    test "a snoozed target is neither underfunded nor met" do
      assert Status.pill(row(available: 100, underfunded: 50, snoozed: true, target: @monthly)) ==
               {"text-bg-success", nil}
    end
  end

  describe "quiet/2" do
    test "red when negative, dimmed at zero, a dot while underfunded up to now or once assigned" do
      assert Status.quiet(row(available: -1), @oct) == %{class: "app-neg", dot: false}
      assert Status.quiet(row(available: 0), @oct) == %{class: "app-zero", dot: false}
      assert Status.quiet(row(available: 5, underfunded: 5), @oct) == %{class: nil, dot: true}
      assert Status.quiet(row(month: @nov, available: 5, underfunded: 5), @oct).dot == false
      assert Status.quiet(row(month: @nov, assigned: 1, underfunded: 5), @oct).dot == true
      assert Status.quiet(row(underfunded: 5, snoozed: true), @oct).dot == false
    end
  end

  describe "target_line/1" do
    test "overspent wins, with the exact amount" do
      assert Status.target_line(row(available: -1_250)) ==
               %{title: "Überzogen 12,50 €", bars: [{100, "bg-danger"}]}
    end

    test "nothing without a target" do
      assert Status.target_line(row(available: 500, activity: -100)) == nil
    end

    test "snoozed, underfunded with the progress, spent, funded with what is spent" do
      assert %{title: "Pausiert", bars: [{100, "bg-secondary"}]} =
               Status.target_line(row(target: @monthly, snoozed: true, underfunded: 10))

      assert %{title: "Noch 50,00 € nötig", bars: [{93, "bg-warning"}]} =
               Status.target_line(row(target: @monthly, underfunded: 5_000, progress: 0.9286))

      assert %{title: "Ausgegeben", bars: [{100, "bg-success progress-bar-striped"}]} =
               Status.target_line(row(target: @monthly, assigned: 1_000, activity: -1_000))

      assert %{
               title: "Finanziert, 29,99 € von 105,55 € ausgegeben",
               bars: [{28, _spent}, {72, "bg-success"}]
             } =
               Status.target_line(
                 row(
                   target: @monthly,
                   carried: 5_555,
                   assigned: 5_000,
                   activity: -2_999,
                   available: 7_556
                 )
               )

      assert %{title: "Finanziert", bars: [{100, "bg-success"}]} =
               Status.target_line(row(target: @monthly, assigned: 100, available: 100))

      assert %{title: "Im Plan"} = Status.target_line(row(target: @yearly, available: 100))
    end
  end

  describe "ready/1" do
    test "red when too much is assigned, as it ended in a past month, green with money, else done" do
      assert Status.ready(%Month{ready_to_assign_shown: -1}) ==
               {"text-danger", "Zu viel verteilt"}

      assert Status.ready(%Month{ready_to_assign_shown: 5, closed: true}) ==
               {"text-body-secondary", "Nicht verteilt am Monatsende"}

      assert Status.ready(%Month{ready_to_assign_shown: 5}) == {"text-success", "Zu verteilen"}
      assert Status.ready(%Month{ready_to_assign_shown: 0}) == {nil, "Alles verteilt ✓"}
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
               %{label: "Verfügbare Mittel", value: 376_126, class: nil},
               %{label: "Überzogen im Sep", value: -1_810, class: "text-danger"},
               %{label: "Zugewiesen", value: -313_071, class: nil},
               %{label: "Für spätere Monate", value: -39_200, class: nil}
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
               %{label: "Verfügbare Mittel", value: -500, class: "text-danger"},
               %{label: "Überzogen im Okt", value: 0, class: nil},
               %{label: "Zugewiesen", value: 0}
             ] = Status.calculation(november)
    end
  end

  test "uncovered/1 says which later months are short and by how much, with the year when it differs" do
    month = %Month{month: @oct, uncovered: [{@nov, 30_000}, {~D[2027-01-01], 5}]}

    assert Status.uncovered(month) == [
             "November nicht gedeckt: es fehlen 300,00 €",
             "Januar 2027 nicht gedeckt: es fehlen 0,05 €"
           ]
  end
end
