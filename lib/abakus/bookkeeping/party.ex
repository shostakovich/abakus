defmodule Abakus.Bookkeeping.Party do
  @moduledoc """
  The sender or the recipient as an invoice names them, kept with the invoice as it was written, so that a later
  change of the settings or the customer leaves the invoice as it was. Only the sender has a tax number and an IBAN.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Abakus.Bookkeeping.{Customer, Settings}

  @primary_key false
  embedded_schema do
    field :name, :string
    field :street, :string
    field :postal_code, :string
    field :city, :string
    field :country, :string, default: "DE"
    field :vat_id, :string
    field :tax_number, :string
    field :iban, :string
  end

  @doc "The sender of the settings."
  def sender(%Settings{} = settings),
    do:
      struct(__MODULE__, Map.take(Map.from_struct(settings), fields()) |> Map.put(:country, "DE"))

  @doc "The recipient of a customer."
  def recipient(%Customer{} = customer),
    do: struct(__MODULE__, Map.take(Map.from_struct(customer), fields() -- [:tax_number, :iban]))

  defp fields, do: __schema__(:fields)

  @doc "Takes the spaces out of `fields` and writes them in capitals, as an IBAN or a VAT id is written."
  def normalize(changeset, fields) do
    Enum.reduce(fields, changeset, fn field, changeset ->
      update_change(
        changeset,
        field,
        &(&1 && &1 |> String.replace(~r/\s/u, "") |> String.upcase())
      )
    end)
  end

  @doc "A VAT id: two letters of its country, then its number."
  def validate_vat_id(changeset),
    do:
      validate_format(changeset, :vat_id, ~r/^[A-Z]{2}[A-Z0-9+*.]{2,12}$/,
        message: "ist keine gültige USt-IdNr."
      )
end
