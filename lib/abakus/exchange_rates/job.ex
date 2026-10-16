defmodule Abakus.ExchangeRates.Job do
  @moduledoc """
  Loads the ECB rates every day at 17:00 local time, an hour after their publication, and at boot
  when the run of the last 17:00 slot is missing, so that a fresh install fills itself.
  """

  alias Abakus.{DailyJob, ExchangeRates, LocalTime}

  @at ~T[17:00:00]

  def child_spec(_opts),
    do: DailyJob.child_spec(name: __MODULE__, at: @at, run: &run/0, at_boot?: &due?/0)

  defp run, do: ExchangeRates.load()

  defp due? do
    last_run = ExchangeRates.last_run()
    DailyJob.missed?(last_run && LocalTime.from_utc(last_run.ran_at), LocalTime.now(), @at)
  end
end
