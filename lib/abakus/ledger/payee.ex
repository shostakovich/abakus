defmodule Abakus.Ledger.Payee do
  @moduledoc """
  Who a transaction is with. Every account has one transfer payee ("Transfer : Girokonto"); a transaction with it
  is a transfer to that account. A hidden payee is no longer suggested; its rename rule is its
  `Abakus.Ledger.PayeeRenameCondition`s. A payee merged into another is deleted with that one as its successor.
  """

  use Abakus.Schema, uuid: true

  import Ecto.Changeset

  alias Abakus.Categories.Category
  alias Abakus.{Ids, Names}
  alias Abakus.Ledger.Account

  schema "payees" do
    field :name, :string
    field :lookup_key, :string
    field :hidden, :boolean, default: false
    field :deleted_at, :utc_datetime_usec

    belongs_to :user, Abakus.Users.User, type: :id
    belongs_to :transfer_account, Account
    belongs_to :last_category, Category
    belongs_to :successor, __MODULE__

    timestamps()
  end

  @doc "Changeset for payees other than transfer payees."
  def changeset(payee, attrs) do
    payee
    |> cast(attrs, [:name, :last_category_id, :hidden])
    |> validate_required([:user_id, :name])
    |> validate_not_transfer()
    |> Names.put_lookup_key()
  end

  @doc "Names the transfer payee after its account."
  def transfer_changeset(payee, %Account{id: account_id, name: account_name}) do
    payee
    |> change(name: transfer_name(account_name), transfer_account_id: account_id)
    |> put_transfer_id(account_id)
    |> Names.put_lookup_key()
    |> unique_constraint(:transfer_account_id)
  end

  defp put_transfer_id(%{data: %{id: nil}} = changeset, account_id),
    do: put_change(changeset, :id, Ids.transfer_payee(account_id))

  defp put_transfer_id(changeset, _account_id), do: changeset

  defp transfer_name(account_name), do: "Transfer : " <> account_name

  defp validate_not_transfer(%{data: %{transfer_account_id: nil}} = changeset), do: changeset

  defp validate_not_transfer(changeset) do
    validate_change(changeset, :name, fn :name, _ -> [name: "folgt dem Kontonamen"] end)
  end
end
