defmodule Abakus.Ledger.TransactionOrigin do
  @moduledoc """
  Where a transaction was imported from: the external id per account and source (FITID, the bank's or YNAB's
  id). A transaction that an import was matched to keeps the import's origin, so a re-import still finds it
  (see docs/adr/0001-transaction-origins.md).
  """

  use Abakus.Schema

  import Ecto.Changeset

  alias Abakus.Ledger.{Account, Transaction}

  schema "transaction_origins" do
    field :source, Ecto.Enum, values: [:ynab, :file, :bank, :api]
    field :external_id, :string

    belongs_to :transaction, Transaction
    belongs_to :account, Account

    timestamps()
  end

  @doc "Changeset for an origin whose `transaction_id` and `account_id` are set."
  def changeset(origin, attrs) do
    origin
    |> cast(attrs, [:source, :external_id])
    |> validate_required([:transaction_id, :account_id, :source, :external_id])
    |> unique_constraint([:account_id, :source, :external_id], error_key: :external_id)
  end
end
