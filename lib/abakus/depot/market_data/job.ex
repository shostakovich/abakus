defmodule Abakus.Depot.MarketData.Job do
  @moduledoc """
  Runs `Abakus.Depot.MarketData.run_daily/1` every day at 18:00 local time, then books the value
  changes into the budget (`Abakus.Depot.BudgetFeed`): Xetra closes at 17:30, the ECB publishes
  around 16:00. At boot it runs at once when the last run is older than the last 18:00 slot.
  There are no retries; the next run fills the gaps.
  """

  alias Abakus.{DailyJob, LocalTime}
  alias Abakus.Depot.{BudgetFeed, MarketData}

  @at ~T[18:00:00]

  def child_spec(_opts),
    do: DailyJob.child_spec(name: __MODULE__, at: @at, run: &run/0, at_boot?: &due?/0)

  @doc "One run: the prices, then the value changes in the budget."
  def run do
    MarketData.run_daily()
    BudgetFeed.book_value_changes()
  end

  defp due? do
    last_run = MarketData.last_run()
    due?(last_run && LocalTime.from_utc(last_run.ran_at), LocalTime.now())
  end

  @doc "Whether the last run, in local time, is older than the last slot before `now`."
  def due?(nil, _now), do: true

  def due?(last_run, now),
    do: NaiveDateTime.before?(last_run, NaiveDateTime.add(LocalTime.next_at(now, @at), -1, :day))
end
