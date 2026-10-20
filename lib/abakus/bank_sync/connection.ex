defmodule Abakus.BankSync.Connection do
  @moduledoc """
  A bank connection: the budget owner's consent at one bank through a provider, valid until a moment, with the
  bank's accounts and the reminders sent before it expires (days before, e.g. 14 and 3).
  """

  use Abakus.Schema

  alias Abakus.BankSync.{LinkedAccount, SyncRun}

  schema "bank_connections" do
    field :provider, Ecto.Enum, values: [:enable_banking]
    field :bank_name, :string
    field :bank_country, :string
    field :session_id, :string, redact: true
    field :valid_until, :utc_datetime_usec
    field :reminders_sent, {:array, :integer}, default: []
    field :last_sync_at, :utc_datetime_usec
    field :last_error, :string

    belongs_to :user, Abakus.Users.User
    has_many :linked_accounts, LinkedAccount, preload_order: [asc: :id]
    has_many :sync_runs, SyncRun

    timestamps()
  end

  @doc "Whether the connection is fetched: an account of its feeds one (preloaded)."
  def fetchable?(%__MODULE__{linked_accounts: linked_accounts}),
    do: Enum.any?(linked_accounts, & &1.account_id)
end
