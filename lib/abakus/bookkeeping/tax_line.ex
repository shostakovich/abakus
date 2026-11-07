defmodule Abakus.Bookkeeping.TaxLine do
  @moduledoc """
  What a transaction, or one part of a split, counts for in the returns: its bookkeeping category and VAT treatment.
  Net and VAT amount follow from the amount (`Abakus.Bookkeeping.Vat.amounts/3`). A line of a split's part
  (`subtransaction_id`) counts while the part is in the split, one of the whole transaction while it is no split.
  """

  use Abakus.Schema, uuid: true

  import Ecto.Changeset

  alias Abakus.Bookkeeping.{Category, Vat}
  alias Abakus.Ledger.{Subtransaction, Transaction}

  schema "bookkeeping_tax_lines" do
    field :category, :string
    field :vat, Ecto.Enum, values: Vat.stored()

    belongs_to :user, Abakus.Users.User, type: :id
    belongs_to :transaction, Transaction
    belongs_to :subtransaction, Subtransaction

    timestamps()
  end

  def changeset(tax_line, attrs) do
    tax_line
    |> cast(attrs, [:category, :vat])
    |> validate_required([:category, :vat])
    |> validate_inclusion(:category, Category.keys())
    |> validate_vat()
    |> unique_constraint(:transaction_id, name: :bookkeeping_tax_lines_transaction_index)
    |> unique_constraint(:subtransaction_id)
  end

  defp validate_vat(changeset) do
    category = Category.get(get_field(changeset, :category))
    vat = get_field(changeset, :vat)

    cond do
      is_nil(category) or is_nil(vat) or Category.fits?(category, vat) -> changeset
      vat == :reverse_charge -> add_error(changeset, :vat, "passt nur zu einer §13b-Kategorie")
      true -> add_error(changeset, :vat, "muss bei einer §13b-Kategorie Reverse Charge sein")
    end
  end
end
