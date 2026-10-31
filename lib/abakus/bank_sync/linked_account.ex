defmodule Abakus.BankSync.LinkedAccount do
  @moduledoc """
  One of a bank connection's accounts, by the provider's id, with its name and IBAN as the bank gives them, and the
  account it feeds from its start date on; without an account it stays unlinked. An account takes one at most.
  `last_fetch_at` is its last successful fetch into that account, which a new account or start date resets.
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
    field :last_fetch_at, :utc_datetime_usec

    belongs_to :connection, Connection
    belongs_to :account, Account, type: Ecto.UUID

    timestamps()
  end

  @doc """
  Changeset for assigning the account and its start date; unlinked, it has no start date. Either changed, the next
  fetch starts at the start date again.
  """
  def assign_changeset(linked_account, attrs) do
    linked_account
    |> cast(attrs, [:account_id, :start_date])
    |> clear_start_date_without_account()
    |> reset_last_fetch_on_change()
    |> then(&if get_field(&1, :account_id), do: validate_required(&1, :start_date), else: &1)
    |> unique_constraint(:account_id)
  end

  defp reset_last_fetch_on_change(changeset) do
    if changed?(changeset, :account_id) or changed?(changeset, :start_date),
      do: put_change(changeset, :last_fetch_at, nil),
      else: changeset
  end

  defp clear_start_date_without_account(changeset) do
    if get_field(changeset, :account_id),
      do: changeset,
      else: put_change(changeset, :start_date, nil)
  end
end
