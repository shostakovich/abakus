defmodule Abakus.Bookkeeping.Disposal do
  @moduledoc """
  How a fixed asset left the register: sold, for example traded in, or withdrawn for private use, on a date, for
  an amount in cents that includes its VAT: the proceeds of a sale, the fair value ("Teilwert") of a withdrawal. A
  transaction that pays a sale can be linked to it; it then carries no tax line of its own.
  """

  use Abakus.Schema, uuid: true

  import Ecto.Changeset
  import Abakus.Bookkeeping.NumberInput

  alias Abakus.Bookkeeping.{FixedAsset, Vat}
  alias Abakus.Money

  @treatments Vat.treatments() -- [:reverse_charge]

  schema "bookkeeping_disposals" do
    field :kind, Ecto.Enum, values: [:sale, :withdrawal], default: :sale
    field :date, :date
    field :amount, :integer
    field :vat, Ecto.Enum, values: Keyword.take(Vat.stored(), @treatments), default: :rate_19

    belongs_to :user, Abakus.Users.User, type: :id
    belongs_to :fixed_asset, FixedAsset
    belongs_to :transaction, Abakus.Ledger.Transaction

    timestamps()
  end

  @doc "The VAT treatments a disposal offers: the rates, no reverse charge."
  def treatments, do: @treatments

  @doc "What the owner fills in; `purchased_on` is the asset's purchase date, which the disposal cannot precede."
  def changeset(disposal, attrs, %Date{} = purchased_on) do
    disposal
    |> cast(attrs, [:kind, :date, :vat, :transaction_id])
    |> cast_cents(attrs, :amount)
    |> validate_required([:kind, :date, :amount, :vat])
    |> validate_number(:amount, greater_than_or_equal_to: 0, less_than: Money.max_cents())
    |> validate_date(purchased_on)
    |> clear_payment()
  end

  defp validate_date(changeset, purchased_on) do
    date = get_field(changeset, :date)

    if date && Date.before?(date, purchased_on),
      do: add_error(changeset, :date, "liegt vor der Anschaffung"),
      else: changeset
  end

  defp clear_payment(changeset) do
    if get_field(changeset, :kind) == :withdrawal,
      do: put_change(changeset, :transaction_id, nil),
      else: changeset
  end
end
