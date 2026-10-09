defmodule Abakus.YnabImport.TargetsTest do
  use ExUnit.Case, async: true

  alias Abakus.YnabImport.Targets

  @monthly %{
    "goal_type" => "NEED",
    "goal_cadence" => 1,
    "goal_cadence_frequency" => 1,
    "goal_needs_whole_amount" => true,
    "goal_target" => 300_000,
    "goal_creation_month" => "2026-08-01"
  }

  @yearly %{
    "goal_type" => "NEED",
    "goal_cadence" => 13,
    "goal_cadence_frequency" => 1,
    "goal_needs_whole_amount" => false,
    "goal_target" => 600_000,
    "goal_target_month" => "2026-12-15",
    "goal_creation_month" => "2026-08-01"
  }

  test "a target starts in its creation month, though earlier months show it" do
    plan = plan(%{"2026-07-01" => @monthly, "2026-08-01" => @monthly, "2026-09-01" => @monthly})

    assert Targets.versions(plan) == [
             {"c",
              [
                %{
                  from_month: ~D[2026-08-01],
                  cadence: :monthly,
                  amount: 30_000,
                  due_on: nil,
                  set_aside: true
                }
              ]}
           ]
  end

  test "a change starts a new version, a removed target ends it" do
    plan =
      plan(%{
        "2026-08-01" => @monthly,
        "2026-09-01" => %{@monthly | "goal_target" => 400_000, "goal_needs_whole_amount" => false},
        "2026-10-01" => %{"goal_type" => nil}
      })

    assert [
             {"c",
              [
                %{amount: 30_000},
                %{from_month: ~D[2026-09-01], amount: 40_000, set_aside: false},
                ended
              ]}
           ] =
             Targets.versions(plan)

    assert ended == %{from_month: ~D[2026-10-01], cadence: :none}
  end

  test "a yearly due date rolled forward by YNAB is the same target, and never lies before the version" do
    plan =
      plan(%{
        "2026-12-01" => @yearly,
        "2027-01-01" => %{@yearly | "goal_target_month" => "2027-12-15"},
        "2027-02-01" => %{@yearly | "goal_target" => 700_000, "goal_target_month" => "2026-12-15"}
      })

    assert [{"c", [first, second]}] = Targets.versions(plan)

    assert %{
             from_month: ~D[2026-12-01],
             cadence: :yearly,
             due_on: ~D[2026-12-15],
             set_aside: false
           } = first

    assert %{from_month: ~D[2027-02-01], amount: 70_000, due_on: ~D[2027-12-15]} = second
  end

  test "a month is snoozed when the snooze date lies in it" do
    snoozed = Map.put(@monthly, "goal_snoozed_at", "2026-09-03T08:00:00.000Z")
    plan = plan(%{"2026-08-01" => @monthly, "2026-09-01" => snoozed, "2026-10-01" => snoozed})

    assert Targets.snoozes(plan) == [{"c", ~D[2026-09-01]}]
  end

  test "deleted and internal categories' goals are left alone, however odd" do
    weekly_snoozed =
      Map.merge(@monthly, %{"goal_cadence" => 2, "goal_snoozed_at" => "2026-09-03T08:00:00.000Z"})

    plan =
      plan(%{"2026-09-01" => @monthly})
      |> Map.update!("categories", fn categories ->
        categories ++
          [
            %{"id" => "gone", "name" => "Kino", "internal" => false, "deleted" => true},
            %{"id" => "split", "name" => "Split", "internal" => true, "deleted" => false}
          ]
      end)
      |> update_in(["months", Access.all(), "categories"], fn categories ->
        categories ++
          [Map.put(weekly_snoozed, "id", "gone"), Map.put(weekly_snoozed, "id", "split")]
      end)

    assert [{"c", [_version]}] = Targets.versions(plan)
    assert Targets.snoozes(plan) == []
  end

  defp plan(goals_by_month) do
    %{
      "categories" => [
        %{"id" => "c", "name" => "🛒 Lebensmittel", "internal" => false, "deleted" => false}
      ],
      "months" =>
        for {month, goals} <- goals_by_month do
          %{
            "month" => month,
            "deleted" => false,
            "categories" => [Map.merge(%{"id" => "c"}, goals)]
          }
        end
    }
  end
end
