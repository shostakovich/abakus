defmodule Abakus.Kasse.Recurring.JobTest do
  use Abakus.DataCase

  import Abakus.KasseFixtures

  alias Abakus.Kasse.{Activities, Expenses, Recurring}
  alias Abakus.Kasse.Recurring.Job
  alias Abakus.Users.Scope

  test "catches up at boot, as the system" do
    h = household()

    expense =
      create!(
        equal(h, "Putzen", 4000, Date.to_iso8601(Date.add(Date.utc_today(), -30)), h.anna, [
          h.anna
        ])
      )

    {:ok, rule, 0} =
      Recurring.create_rule(scope_of(h.anna), expense, :weekly, today: expense.date)

    Expenses.subscribe(Scope.system())

    start_supervised!(Job)
    :sys.get_state(Job)

    assert_received {:expenses_changed, _ids}
    refute Date.before?(Recurring.get_rule!(Scope.system(), rule.id).next_date, Date.utc_today())

    assert [_ | _] =
             occurrences =
             Activities.list_activities(Scope.system(), action: :expense_created)
             |> Enum.reject(&(&1.expense_id == expense.id))

    assert Enum.all?(occurrences, &is_nil(&1.actor_id))
  end

  describe "next_tick/3" do
    test "keeps to the interval" do
      assert Job.next_tick(1000, 1500, 1000) == 2000
      assert Job.next_tick(2000, 2000, 1000) == 3000
    end

    test "drops the ticks an overrunning run missed" do
      assert Job.next_tick(2000, 4500, 1000) == 5000
    end
  end
end
