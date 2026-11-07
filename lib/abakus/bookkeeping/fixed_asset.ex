defmodule Abakus.Bookkeeping.FixedAsset do
  @moduledoc """
  A purchase the business uses for years, in the asset register: its name, purchase date, net amount in cents and
  useful life in years. Up to the low-value limit it is expensed at once and needs no useful life
  (`Abakus.Bookkeeping.Depreciation`). It leaves the register by its disposal.
  """

  use Abakus.Schema, uuid: true

  import Ecto.Changeset
  import Abakus.Bookkeeping.NumberInput

  alias Abakus.Bookkeeping.{Depreciation, Disposal}
  alias Abakus.Money

  schema "bookkeeping_fixed_assets" do
    field :name, :string
    field :purchased_on, :date
    field :net, :integer
    field :useful_life, :integer

    belongs_to :user, Abakus.Users.User, type: :id
    has_one :disposal, Disposal

    timestamps()
  end

  def changeset(asset, attrs) do
    asset
    |> cast(attrs, [:name, :purchased_on, :useful_life])
    |> cast_cents(attrs, :net)
    |> update_change(:name, &String.trim/1)
    |> validate_required([:name, :purchased_on, :net])
    |> validate_length(:name, max: 200)
    |> validate_number(:net, greater_than: 0, less_than: Money.max_cents())
    |> validate_number(:useful_life, greater_than: 0, less_than_or_equal_to: 50)
    |> validate_useful_life()
  end

  defp validate_useful_life(changeset) do
    net = get_field(changeset, :net)

    if is_integer(net) and not Depreciation.low_value?(net),
      do: validate_required(changeset, :useful_life),
      else: changeset
  end
end
