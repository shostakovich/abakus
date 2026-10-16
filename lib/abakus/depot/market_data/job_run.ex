defmodule Abakus.Depot.MarketData.JobRun do
  @moduledoc "When a job last ran."
  use Abakus.Schema

  schema "depot_job_runs" do
    field :name, :string
    field :ran_at, :utc_datetime_usec
  end
end
