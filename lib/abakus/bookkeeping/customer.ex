defmodule Abakus.Bookkeeping.Customer do
  @moduledoc """
  Whom the user's invoices go to: a name, an address and, for a business abroad, its VAT id. One taken over from
  Lexoffice keeps its contact's id there.
  """

  use Abakus.Schema, uuid: true

  import Ecto.Changeset

  alias Abakus.Bookkeeping.{Countries, Party}

  schema "bookkeeping_customers" do
    field :name, :string
    field :street, :string
    field :postal_code, :string
    field :city, :string
    field :country, :string, default: "DE"
    field :vat_id, :string
    field :lexoffice_id, :string

    belongs_to :user, Abakus.Users.User, type: :id

    timestamps()
  end

  def changeset(customer, attrs) do
    customer
    |> cast(attrs, [:name, :street, :postal_code, :city, :country, :vat_id])
    |> update_change(:name, &(&1 && String.trim(&1)))
    |> Party.normalize([:vat_id])
    |> validate_required([:name, :street, :postal_code, :city, :country])
    |> validate_length(:name, max: 200)
    |> validate_inclusion(:country, Countries.codes())
    |> Party.validate_vat_id()
  end

  @doc "A Lexoffice contact as it is there, which may lack an address."
  def import_changeset(customer, attrs) do
    customer
    |> cast(attrs, [:name, :street, :postal_code, :city, :country, :vat_id, :lexoffice_id])
    |> Party.normalize([:vat_id])
    |> validate_required([:name, :country])
    |> unique_constraint(:lexoffice_id, name: :bookkeeping_customers_user_id_lexoffice_id_index)
  end
end
