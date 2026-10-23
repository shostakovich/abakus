defmodule Abakus.BankSync.SyncRun do
  @moduledoc """
  One fetch of a bank connection, scheduled or manual ("Jetzt abrufen"): when it started, how many transactions came
  in new and as match proposals, and its error if it failed.
  """

  use Abakus.Schema

  alias Abakus.BankSync.Connection

  schema "bank_sync_runs" do
    field :started_at, :utc_datetime_usec
    field :trigger, Ecto.Enum, values: [:scheduled, :manual]
    field :new, :integer, default: 0
    field :matched, :integer, default: 0
    field :error, :string

    belongs_to :connection, Connection

    timestamps()
  end
end
