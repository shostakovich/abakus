defmodule Abakus.Depot.MarketData.JobRun do
  @moduledoc "When a job last ran, and the error of its exchange rate fetch, if any."
  use Abakus.Schema

  schema "depot_job_runs" do
    field :name, :string
    field :ran_at, :utc_datetime_usec
    field :error, :string
  end
end
