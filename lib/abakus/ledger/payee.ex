defmodule Abakus.Ledger.Payee do
  @moduledoc """
  Who a transaction is with. Every account has one transfer payee ("Transfer : Girokonto"); a transaction with it
  is a transfer to that account.
  """

  use Abakus.Schema

  import Ecto.Changeset

  alias Abakus.Categories.Category
  alias Abakus.Ledger.Account
  alias Abakus.Names

  schema "payees" do
    field :name, :string
    field :lookup_key, :string

    belongs_to :transfer_account, Account
    belongs_to :last_category, Category

    timestamps()
  end

  @doc "Changeset for payees other than transfer payees."
  def changeset(payee, attrs) do
    payee
    |> cast(attrs, [:name, :last_category_id])
    |> validate_required([:name])
    |> validate_not_transfer()
    |> Names.put_lookup_key()
    |> unique_constraint(:name, name: :payees_lookup_key_index)
  end

  @doc "Names the transfer payee after its account."
  def transfer_changeset(payee, %Account{id: account_id, name: account_name}) do
    payee
    |> change(name: transfer_name(account_name), transfer_account_id: account_id)
    |> Names.put_lookup_key()
    |> unique_constraint(:transfer_account_id)
  end

  defp transfer_name(account_name), do: "Transfer : " <> account_name

  defp validate_not_transfer(%{data: %{transfer_account_id: nil}} = changeset), do: changeset

  defp validate_not_transfer(changeset) do
    validate_change(changeset, :name, fn :name, _ -> [name: "folgt dem Kontonamen"] end)
  end
end
