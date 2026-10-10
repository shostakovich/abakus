defmodule Abakus.Ledger.BankBalance do
  @moduledoc """
  What the bank reports an account holds on a date: a file's ledger balance (`LEDGERBAL`) or, with bank sync, the
  bank's balance. Reconciling offers the latest one. One per account, source and date.
  """

  use Abakus.Schema

  import Ecto.Changeset

  alias Abakus.Amount
  alias Abakus.Ledger.Account

  schema "bank_balances" do
    field :source, Ecto.Enum, values: [:file, :bank]
    field :date, :date
    field :amount, :integer

    belongs_to :account, Account

    timestamps()
  end

  @doc "Changeset for a balance whose `account_id` is set."
  def changeset(balance, attrs) do
    balance
    |> cast(attrs, [:source, :date, :amount])
    |> validate_required([:account_id, :source, :date, :amount])
    |> Amount.validate()
  end
end
