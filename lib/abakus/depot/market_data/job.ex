defmodule Abakus.Depot.MarketData.Job do
  @moduledoc """
  Runs `Abakus.Depot.MarketData.run_daily/1` every day at 18:00 local time, then books the value
  changes into the budget (`Abakus.Depot.BudgetFeed`): Xetra closes at 17:30, and the ECB rates
  come at 17:00 (`Abakus.ExchangeRates.Job`). At boot it runs at once when the last run is older
  than the last 18:00 slot, and otherwise books only the value changes, which open the accounts
  of new portfolios, e.g. after an update. There are no retries; the next run fills the gaps.
  """

  alias Abakus.{DailyJob, LocalTime}
  alias Abakus.Depot.{BudgetFeed, MarketData}

  @at ~T[18:00:00]

  def child_spec(_opts),
    do: DailyJob.child_spec(name: __MODULE__, at: @at, run: &run/0, at_boot?: &boot/0)

  @doc "One run: the prices, then the value changes in the budget."
  def run do
    MarketData.run_daily()
    BudgetFeed.book_value_changes()
  end

  defp boot do
    due? = due?()
    if !due?, do: BudgetFeed.book_value_changes()
    due?
  end

  defp due? do
    last_run = MarketData.last_run()
    due?(last_run && LocalTime.from_utc(last_run.ran_at), LocalTime.now())
  end

  @doc "Whether the last run, in local time, is older than the last slot before `now`."
  def due?(last_run, now), do: DailyJob.missed?(last_run, now, @at)
end
