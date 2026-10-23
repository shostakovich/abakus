defmodule Abakus.Depot.MarketData.Job do
  @moduledoc """
  Runs `Abakus.Depot.MarketData.run_daily/1` every day at 18:00 local time: Xetra closes at 17:30, and the ECB rates
  come at 17:00 (`Abakus.ExchangeRates.Job`). At boot it runs at once when the last run is older than the last 18:00
  slot. There are no retries; the next run fills the gaps.
  """

  alias Abakus.{DailyJob, LocalTime}
  alias Abakus.Depot.MarketData

  @at ~T[18:00:00]

  def child_spec(_opts),
    do: DailyJob.child_spec(name: __MODULE__, at: @at, run: &run/0, at_boot?: &due?/0)

  defp run, do: MarketData.run_daily()

  defp due? do
    last_run = MarketData.last_run()
    due?(last_run && LocalTime.from_utc(last_run.ran_at), LocalTime.now())
  end

  @doc "Whether the last run, in local time, is older than the last slot before `now`."
  def due?(last_run, now), do: DailyJob.missed?(last_run, now, @at)
end
