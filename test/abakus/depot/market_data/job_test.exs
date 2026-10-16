defmodule Abakus.Depot.MarketData.JobTest do
  use Abakus.DataCase

  alias Abakus.Depot.{FakeRateSource, MarketData}
  alias Abakus.Depot.MarketData.{Job, JobRun}

  describe "at boot" do
    test "runs at once when a slot was missed" do
      Repo.insert!(%JobRun{
        name: "daily",
        ran_at: DateTime.add(DateTime.utc_now(:microsecond), -2, :day)
      })

      FakeRateSource.stub(fn _from -> {:ok, []} end)
      MarketData.subscribe()

      start_supervised!(Job)

      assert_receive :market_data_updated
      assert_received {:rates, _from}
    end

    test "waits when the last slot already ran" do
      Repo.insert!(%JobRun{name: "daily", ran_at: DateTime.utc_now(:microsecond)})
      FakeRateSource.stub(fn _from -> {:ok, []} end)

      start_supervised!(Job)

      refute_receive {:rates, _from}, 100
    end
  end

  describe "due?/2" do
    test "runs at boot when the last run is older than the last 18:00 slot" do
      assert Job.due?(~N[2026-10-08 18:00:05], ~N[2026-10-09 18:30:00])
      assert Job.due?(~N[2026-10-07 18:00:05], ~N[2026-10-09 10:00:00])
      assert Job.due?(nil, ~N[2026-10-09 10:00:00])
    end

    test "waits when the last slot already ran" do
      refute Job.due?(~N[2026-10-08 18:00:05], ~N[2026-10-09 10:00:00])
      refute Job.due?(~N[2026-10-09 18:00:00], ~N[2026-10-09 18:30:00])
    end
  end
end
