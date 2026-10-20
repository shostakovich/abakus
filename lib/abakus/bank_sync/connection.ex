defmodule Abakus.BankSync.Connection do
  @moduledoc """
  A bank connection: the budget owner's consent at one bank through a provider, valid until a moment, with the
  bank's accounts.
  """

  use Abakus.Schema

  alias Abakus.BankSync.{LinkedAccount, SyncRun}
  alias Abakus.LocalTime

  schema "bank_connections" do
    field :provider, Ecto.Enum, values: [:enable_banking]
    field :bank_name, :string
    field :bank_country, :string
    field :session_id, :string, redact: true
    field :valid_until, :utc_datetime_usec
    field :last_sync_at, :utc_datetime_usec
    field :last_error, :string

    belongs_to :user, Abakus.Users.User
    has_many :linked_accounts, LinkedAccount, preload_order: [asc: :id]
    has_many :sync_runs, SyncRun

    timestamps()
  end

  @doc "Whether the consent has ended."
  def expired?(%__MODULE__{valid_until: valid_until}),
    do: not DateTime.after?(valid_until, LocalTime.utc_now())

  @doc "Whether the connection is fetched: its consent has not ended and an account of its feeds one (preloaded)."
  def fetchable?(%__MODULE__{linked_accounts: linked_accounts} = connection),
    do: not expired?(connection) and Enum.any?(linked_accounts, & &1.account_id)

  @doc "The days from `today` to the local day the consent ends; negative once that day has passed."
  def days_left(%__MODULE__{valid_until: valid_until}, today),
    do: Date.diff(LocalTime.date(valid_until), today)
end
