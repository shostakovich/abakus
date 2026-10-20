defmodule Abakus.BankSync.LinkedAccount do
  @moduledoc """
  One of a bank connection's accounts, by the provider's id, with its name and IBAN as the bank gives them, and the
  account it feeds from its start date on; without an account it stays unlinked. An account takes one at most.
  """

  use Abakus.Schema

  import Ecto.Changeset

  alias Abakus.BankSync.Connection
  alias Abakus.Ledger.Account

  schema "bank_linked_accounts" do
    field :provider_account_id, :string
    field :name, :string
    field :iban, :string
    field :start_date, :date

    belongs_to :connection, Connection
    belongs_to :account, Account

    timestamps()
  end

  @doc "Changeset for assigning the account and its start date; unlinked, it has no start date."
  def assign_changeset(linked_account, attrs) do
    linked_account
    |> cast(attrs, [:account_id, :start_date])
    |> clear_start_date_without_account()
    |> then(&if get_field(&1, :account_id), do: validate_required(&1, :start_date), else: &1)
    |> unique_constraint(:account_id)
  end

  defp clear_start_date_without_account(changeset) do
    if get_field(changeset, :account_id),
      do: changeset,
      else: put_change(changeset, :start_date, nil)
  end
end
