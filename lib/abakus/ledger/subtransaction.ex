defmodule Abakus.Ledger.Subtransaction do
  @moduledoc """
  A part of a split transaction, kept in the split's order (`position`). A subtransaction with a transfer payee is
  a transfer of its own, as in YNAB: `transfer_transaction_id` points to its counterpart, which the Ledger keeps.
  Subtransactions go with their transaction: deleted with its row, and soft-deleted with it.
  """

  use Abakus.Schema

  import Ecto.Changeset

  alias Abakus.Amount
  alias Abakus.Categories.Category
  alias Abakus.Ledger.{Payee, Transaction}

  schema "subtransactions" do
    field :position, :integer, default: 0
    field :amount, :integer
    field :memo, :string

    # See Transaction: the counterpart's category for a transfer from a tracking account.
    field :counterpart_category_id, :id, virtual: true

    belongs_to :transaction, Transaction
    belongs_to :category, Category
    belongs_to :payee, Payee
    belongs_to :transfer_transaction, Transaction

    timestamps()
  end

  @doc "Changeset for the subtransaction at `position` in its split."
  def changeset(subtransaction, attrs, position) do
    subtransaction
    |> cast(attrs, [:amount, :category_id, :payee_id, :memo, :counterpart_category_id])
    |> put_change(:position, position)
    |> validate_required([:amount])
    |> Amount.validate()
  end
end
