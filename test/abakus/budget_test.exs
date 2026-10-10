defmodule Abakus.BudgetTest do
  use ExUnit.Case, async: true

  alias Abakus.Budget
  alias Abakus.Budget.{CategoryMonth, Month}

  @sep ~D[2026-09-01]
  @oct ~D[2026-10-01]
  @nov ~D[2026-11-01]
  @dec ~D[2026-12-01]

  defp budget(attrs) do
    struct!(%Budget{categories: [%{id: 1, hidden: false}, %{id: 2, hidden: false}]}, attrs)
  end

  defp months(budget, current \\ @oct, through \\ nil),
    do: Map.new(Budget.months(budget, current, through), &{&1.month, &1})

  defp row(%Month{categories: rows}, id), do: Enum.find(rows, &(&1.category_id == id))

  defp target(attrs),
    do:
      Enum.into(attrs, %{
        from_month: @sep,
        cadence: :monthly,
        due_on: nil,
        repeats_yearly: false,
        set_aside: true
      })

  defp yearly(attrs), do: target([cadence: :by_date, repeats_yearly: true] ++ attrs)

  describe "months/3" do
    test "carries what is available and starts an overspent category at zero" do
      months =
        months(
          budget(
            income: %{@sep => 10_000},
            assigned: %{{1, @sep} => 3_000, {2, @sep} => 1_000, {1, @oct} => 500},
            activity: %{{1, @sep} => -1_000, {2, @sep} => -1_500, {2, @oct} => -200}
          )
        )

      assert %CategoryMonth{carried: 0, available: 2_000} = row(months[@sep], 1)

      assert %CategoryMonth{carried: 2_000, assigned: 500, available: 2_500} =
               row(months[@oct], 1)

      assert %CategoryMonth{available: -500} = row(months[@sep], 2)
      assert %CategoryMonth{carried: 0, available: -200} = row(months[@oct], 2)
    end

    test "takes overspending off next month's Ready to Assign, as YNAB's to_be_budgeted" do
      months =
        months(
          budget(
            income: %{@sep => 10_000, @oct => 2_000},
            assigned: %{{1, @sep} => 3_000, {1, @oct} => 1_000},
            activity: %{{1, @sep} => -4_000, {nil, @sep} => -500}
          )
        )

      assert %Month{ready_to_assign: 7_000, overspent: 1_500} = months[@sep]

      assert %Month{
               not_assigned_last_month: 7_000,
               overspent_last_month: 1_500,
               income: 2_000,
               assigned: 1_000,
               ready_to_assign: 6_500
             } = months[@oct]
    end

    test "shows Ready to Assign less what later months have, and as it ended in a closed month" do
      months =
        months(
          budget(income: %{@sep => 10_000}, assigned: %{{1, @oct} => 1_000, {1, @dec} => 3_000})
        )

      assert %Month{closed: true, assigned_in_future: 4_000, ready_to_assign_shown: 10_000} =
               months[@sep]

      assert %Month{closed: false, assigned_in_future: 3_000, ready_to_assign_shown: 6_000} =
               months[@oct]

      assert %Month{ready_to_assign_shown: 6_000} = months[@nov]
      assert %Month{assigned_in_future: 0, ready_to_assign_shown: 6_000} = months[@dec]
    end

    test "lets assignments push Ready to Assign below zero" do
      months = months(budget(income: %{@oct => 1_000}, assigned: %{{1, @oct} => 5_000}))

      assert months[@oct].ready_to_assign_shown == -4_000
    end

    test "lists the later months that are not covered, up to the last one that changes" do
      months =
        months(
          budget(
            income: %{@oct => 10_000},
            assigned: %{{1, @oct} => 4_000, {2, @nov} => 5_000, {2, @dec} => 2_000},
            activity: %{{1, @oct} => -8_000}
          )
        )

      assert months[@oct].uncovered == [{@nov, 3_000}, {@dec, 5_000}]
      assert months[@nov].uncovered == [{@dec, 5_000}]
      assert months[@dec].uncovered == []
    end

    test "lists a month with data that only repeats the shortfall, not the empty months after it" do
      months =
        months(
          budget(
            income: %{@oct => 10_000, @dec => 2_000},
            assigned: %{{1, @oct} => 4_000, {2, @nov} => 9_000, {2, @dec} => 2_000},
            activity: %{{1, @oct} => -8_000}
          )
        )

      assert months[@oct].uncovered == [{@nov, 7_000}, {@dec, 7_000}]
      assert months[~D[2027-01-01]].ready_to_assign == -7_000
    end

    test "runs from the first month with data to the month after the last, or further when asked" do
      budget = budget(activity: %{{1, @oct} => -100})

      assert Enum.map(Budget.months(budget, @oct, nil), & &1.month) == [@oct, @nov]
      assert Enum.map(Budget.months(budget, @oct, @sep), & &1.month) == [@sep, @oct, @nov]

      assert Enum.map(Budget.months(budget, @oct, ~D[2026-12-15]), & &1.month) ==
               [@oct, @nov, @dec]

      assert Enum.map(Budget.months(%Budget{}, ~D[2026-10-09], nil), & &1.month) == [@oct]
    end

    test "sums the month over all categories, the uncategorised row included" do
      month =
        months(
          budget(
            assigned: %{{1, @oct} => 1_000, {2, @oct} => 500},
            activity: %{{1, @oct} => -300, {nil, @oct} => -200}
          )
        )[@oct]

      assert %Month{assigned: 1_500, activity: -500, available: 1_000, overspent: 200} = month

      assert %CategoryMonth{category_id: nil, activity: -200, available: -200} =
               month.uncategorised
    end

    test "totals what is carried and what the targets need, snoozed ones aside" do
      month =
        months(
          budget(
            assigned: %{{1, @sep} => 2_000},
            targets: %{1 => [target(amount: 1_000)], 2 => [target(amount: 3_000)]},
            snoozes: MapSet.new([{2, @oct}])
          )
        )[@oct]

      assert %Month{carried: 2_000, needed: 1_000, underfunded: 1_000} = month
    end
  end

  describe "targets" do
    test "monthly set aside needs the amount, whatever is carried" do
      months =
        months(
          budget(
            targets: %{1 => [target(amount: 5_000)]},
            assigned: %{{1, @sep} => 8_000, {1, @oct} => 2_000}
          )
        )

      assert %CategoryMonth{needed: 5_000, underfunded: 0, progress: 1.0} = row(months[@sep], 1)

      assert %CategoryMonth{needed: 5_000, underfunded: 3_000, progress: 0.4} =
               row(months[@oct], 1)
    end

    test "monthly refill needs what is missing from the carry" do
      months =
        months(
          budget(
            targets: %{1 => [target(amount: 5_000, set_aside: false)]},
            assigned: %{{1, @sep} => 3_000},
            activity: %{{1, @sep} => -1_000}
          )
        )

      assert %CategoryMonth{needed: 5_000, underfunded: 2_000} = row(months[@sep], 1)

      assert %CategoryMonth{needed: 3_000, underfunded: 3_000, progress: +0.0} =
               row(months[@oct], 1)
    end

    test "a yearly target spreads what is missing over the months up to its due month, rounded up" do
      targets = %{1 => [yearly(amount: 10_000, due_on: ~D[2026-12-24])]}
      months = months(budget(targets: targets, assigned: %{{1, @sep} => 2_000}))

      assert %CategoryMonth{needed: 2_500, underfunded: 500} = row(months[@sep], 1)

      assert %CategoryMonth{needed: 2_667, underfunded: 2_667, progress: 0.2} =
               row(months[@oct], 1)
    end

    test "a yearly refill target counts what is carried" do
      targets = %{
        1 => [yearly(amount: 10_000, due_on: ~D[2026-11-30], set_aside: false)]
      }

      months =
        months(
          budget(
            targets: targets,
            assigned: %{{1, @sep} => 6_000},
            activity: %{{1, @sep} => -2_000}
          )
        )

      assert %CategoryMonth{needed: 3_000, underfunded: 3_000, progress: 0.4} =
               row(months[@oct], 1)
    end

    # As YNAB reports it: taking out of a surplus is underfunded only below the amount.
    test "a monthly refill target counts a surplus against money taken out" do
      months =
        months(
          budget(
            targets: %{
              1 => [target(amount: 5_000, set_aside: false)],
              2 => [target(amount: 5_000, set_aside: false)]
            },
            assigned: %{
              {1, @sep} => 8_000,
              {1, @oct} => -2_000,
              {2, @sep} => 8_000,
              {2, @oct} => -4_000
            }
          )
        )

      assert %CategoryMonth{needed: 0, underfunded: 0, progress: 1.0} = row(months[@oct], 1)
      assert %CategoryMonth{needed: 0, underfunded: 1_000, progress: +0.0} = row(months[@oct], 2)
    end

    test "a yearly refill target counts a surplus against money taken out" do
      yearly = yearly(amount: 10_000, due_on: ~D[2026-11-30], set_aside: false)

      months =
        months(
          budget(
            targets: %{1 => [yearly], 2 => [yearly]},
            assigned: %{
              {1, @sep} => 15_000,
              {1, @oct} => -5_000,
              {2, @sep} => 15_000,
              {2, @oct} => -6_000
            }
          )
        )

      assert %CategoryMonth{needed: 0, underfunded: 0} = row(months[@oct], 1)
      assert %CategoryMonth{needed: 0, underfunded: 1_000} = row(months[@oct], 2)
    end

    test "after its due month a yearly target starts its next cycle" do
      targets = %{1 => [yearly(amount: 12_000, due_on: ~D[2026-09-15])]}
      months = months(budget(targets: targets, assigned: %{{1, @sep} => 12_000}))

      assert %CategoryMonth{needed: 12_000, underfunded: 0} = row(months[@sep], 1)
      assert %CategoryMonth{needed: 1_000} = row(months[@oct], 1)
    end

    test "a yearly target's first cycle begins with the target, even more than a year before it is due" do
      targets = %{
        1 => [yearly(from_month: @oct, amount: 120_000, due_on: ~D[2027-12-15])]
      }

      assigned = Map.new([@oct, @nov, @dec], &{{1, &1}, 8_000})
      months = months(budget(targets: targets, assigned: assigned), @oct, ~D[2027-01-01])

      for month <- [@oct, @nov, @dec], do: assert(row(months[month], 1).needed == 8_000)
      assert %CategoryMonth{needed: 8_000, progress: 0.2} = row(months[~D[2027-01-01]], 1)
    end

    test "a yearly set-aside target counts nothing assigned before it began, and keeps counting when changed" do
      targets = %{
        1 => [
          yearly(from_month: @sep, amount: 60_000, due_on: ~D[2026-12-01]),
          yearly(from_month: @nov, amount: 90_000, due_on: ~D[2026-12-01])
        ]
      }

      assigned = %{{1, ~D[2026-08-01]} => 5_000, {1, @sep} => 20_000, {1, @oct} => 20_000}
      months = months(budget(targets: targets, assigned: assigned))

      assert row(months[@sep], 1).needed == 15_000
      assert row(months[@nov], 1).needed == 25_000
    end

    test "a target by a date spreads what is missing" do
      targets = %{
        1 => [
          target(from_month: @oct, cadence: :by_date, amount: 120_000, due_on: ~D[2027-06-01])
        ]
      }

      months = months(budget(targets: targets), @oct, @nov)

      assert %CategoryMonth{needed: 13_334, underfunded: 13_334} = row(months[@oct], 1)
      assert %CategoryMonth{needed: 15_000, underfunded: 15_000} = row(months[@nov], 1)
    end

    test "the bar of a target by a date shows the whole amount" do
      targets = %{
        1 => [
          target(from_month: @oct, cadence: :by_date, amount: 120_000, due_on: ~D[2027-06-01])
        ]
      }

      months = months(budget(targets: targets, assigned: %{{1, @oct} => 8_000}))

      assert %CategoryMonth{saved: 8_000, underfunded: 5_334} = row(months[@oct], 1)
      assert_in_delta row(months[@oct], 1).progress, 8_000 / 120_000, 1.0e-9
    end

    test "only a target by a date counts what is saved" do
      months = months(budget(targets: %{1 => [target(amount: 5_000)]}))

      assert %CategoryMonth{saved: nil} = row(months[@oct], 1)
      assert %CategoryMonth{saved: nil} = row(months[@oct], 2)
    end

    test "a target by a date without repeating ends after its month" do
      targets = %{
        1 => [target(from_month: @oct, cadence: :by_date, amount: 30_000, due_on: ~D[2027-03-01])]
      }

      assigned = %{{1, ~D[2027-03-01]} => 10_000, {1, ~D[2027-04-01]} => -5_000}
      months = months(budget(targets: targets, assigned: assigned), @oct, ~D[2027-05-01])

      assert %CategoryMonth{needed: 30_000, underfunded: 20_000} = row(months[~D[2027-03-01]], 1)

      for month <- [~D[2027-04-01], ~D[2027-05-01]] do
        assert %CategoryMonth{target: %{amount: 30_000}, needed: 0, underfunded: 0} =
                 row(months[month], 1)
      end
    end

    test "a repeating target starts again" do
      targets = %{1 => [yearly(from_month: @oct, amount: 30_000, due_on: ~D[2027-03-01])]}
      months = months(budget(targets: targets), @oct, ~D[2028-03-01])

      assert row(months[~D[2027-03-01]], 1).needed == 30_000
      assert %CategoryMonth{needed: 2_500, underfunded: 2_500} = row(months[~D[2027-04-01]], 1)
      assert row(months[~D[2028-03-01]], 1).needed == 30_000
    end

    test "a new target by a date after a due month starts afresh" do
      targets = %{
        1 => [
          target(from_month: @oct, cadence: :by_date, amount: 30_000, due_on: ~D[2026-12-01]),
          target(
            from_month: ~D[2027-01-01],
            cadence: :by_date,
            amount: 60_000,
            due_on: ~D[2027-06-01]
          )
        ]
      }

      assigned = Map.new([@oct, @nov, @dec], &{{1, &1}, 10_000})
      months = months(budget(targets: targets, assigned: assigned), @oct, ~D[2027-01-01])

      assert %CategoryMonth{needed: 10_000, saved: 0} = row(months[~D[2027-01-01]], 1)
    end

    test "a repeating target changed after its due month counts only the new cycle" do
      targets = %{
        1 => [
          yearly(from_month: @oct, amount: 3_000, due_on: ~D[2026-12-01]),
          yearly(from_month: ~D[2027-02-01], amount: 24_000, due_on: ~D[2027-12-01])
        ]
      }

      assigned =
        Map.new([@oct, @nov, @dec], &{{1, &1}, 1_000}) |> Map.put({1, ~D[2027-01-01]}, 2_000)

      months = months(budget(targets: targets, assigned: assigned), @oct, ~D[2027-02-01])

      assert %CategoryMonth{needed: 2_000, saved: 2_000} = row(months[~D[2027-02-01]], 1)
    end

    test "hidden categories leave the month's needed and underfunded totals" do
      months =
        months(
          budget(
            categories: [%{id: 1, hidden: true}, %{id: 2, hidden: false}],
            targets: %{1 => [target(amount: 9_000)], 2 => [target(amount: 4_000)]}
          )
        )

      assert %Month{needed: 4_000, underfunded: 4_000} = months[@oct]
      assert %CategoryMonth{underfunded: 9_000} = row(months[@oct], 1)
    end

    test "applies the version in effect, none before the first or after cadence none" do
      targets = %{
        1 => [
          target(from_month: @nov, amount: 1_000),
          target(from_month: @dec, cadence: :none, amount: nil)
        ]
      }

      months = months(budget(targets: targets), @oct, @dec)

      assert %CategoryMonth{target: nil, needed: 0, progress: nil} = row(months[@oct], 1)
      assert %CategoryMonth{target: %{amount: 1_000}, needed: 1_000} = row(months[@nov], 1)
      assert %CategoryMonth{target: nil, needed: 0, underfunded: 0} = row(months[@dec], 1)
    end

    # As in YNAB: its inspector still asks for the amount, the list shows the month as snoozed.
    test "a snoozed target still says what is missing, but leaves the month's underfunded total" do
      months =
        months(
          budget(targets: %{1 => [target(amount: 5_000)]}, snoozes: MapSet.new([{1, @oct}])),
          @oct,
          @nov
        )

      assert %CategoryMonth{snoozed: true, needed: 5_000, underfunded: 5_000, progress: +0.0} =
               row(months[@oct], 1)

      assert months[@oct].underfunded == 0
      assert %CategoryMonth{snoozed: false, underfunded: 5_000} = row(months[@nov], 1)
      assert months[@nov].underfunded == 5_000
    end
  end

  describe "fill_underfunded/4" do
    test "fills in budget order as far as Ready to Assign reaches, skipping hidden categories" do
      budget =
        budget(
          categories: [%{id: 1, hidden: true}, %{id: 2, hidden: false}, %{id: 3, hidden: false}],
          income: %{@oct => 5_000},
          assigned: %{{2, @oct} => 1_000},
          targets: %{
            1 => [target(amount: 9_000)],
            2 => [target(amount: 4_000)],
            3 => [target(amount: 4_000)]
          }
        )

      assert Budget.fill_underfunded(budget, @oct, @oct) == [{2, 4_000}, {3, 1_000}]
    end

    test "skips snoozed categories" do
      budget =
        budget(
          income: %{@oct => 10_000},
          targets: %{1 => [target(amount: 4_000)], 2 => [target(amount: 3_000)]},
          snoozes: MapSet.new([{1, @oct}])
        )

      assert Budget.fill_underfunded(budget, @oct, @oct) == [{2, 3_000}]
    end

    test "keeps what later months have and assigns nothing without money" do
      budget =
        budget(
          income: %{@oct => 5_000},
          assigned: %{{2, @nov} => 5_000},
          targets: %{1 => [target(amount: 4_000)]}
        )

      assert Budget.fill_underfunded(budget, @oct, @oct) == []
    end

    test "takes nothing that later months have in a closed month either" do
      budget =
        budget(
          income: %{@sep => 5_000},
          assigned: %{{2, @oct} => 5_000},
          targets: %{1 => [target(amount: 4_000)]}
        )

      assert Budget.fill_underfunded(budget, @sep, @oct) == []
    end

    test "fills only the category asked for" do
      budget =
        budget(
          income: %{@oct => 10_000},
          targets: %{1 => [target(amount: 4_000)], 2 => [target(amount: 3_000)]}
        )

      assert Budget.fill_underfunded(budget, @oct, @oct, 2) == [{2, 3_000}]
    end
  end
end
