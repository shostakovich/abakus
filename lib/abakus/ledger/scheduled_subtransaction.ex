defmodule Abakus.Ledger.ScheduledSubtransaction do
  @moduledoc "A part of a split scheduled transaction, in the split's order; entered as a subtransaction."

  use Abakus.Schema, uuid: true

  import Ecto.Changeset

  alias Abakus.Amount
  alias Abakus.Categories.Category
  alias Abakus.Ledger.{Payee, ScheduledTransaction}

  schema "scheduled_subtransactions" do
    field :position, :integer, default: 0
    field :amount, :integer
    field :memo, :string

    belongs_to :scheduled_transaction, ScheduledTransaction
    belongs_to :payee, Payee
    belongs_to :category, Category

    timestamps()
  end

  @doc "Changeset for the part at `position` in its split."
  def changeset(part, attrs, position) do
    part
    |> cast(attrs, [:amount, :payee_id, :category_id, :memo])
    |> put_change(:position, position)
    |> validate_required([:amount])
    |> Amount.validate()
  end
end
