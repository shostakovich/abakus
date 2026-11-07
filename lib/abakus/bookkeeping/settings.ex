defmodule Abakus.Bookkeeping.Settings do
  @moduledoc """
  A user's bookkeeping settings: the sender their invoices name, with the tax number or VAT id an invoice must
  carry, the IBAN it is paid to and the days until it is due.
  """

  use Abakus.Schema, uuid: true

  import Ecto.Changeset

  alias Abakus.Bookkeeping.Party

  schema "bookkeeping_settings" do
    field :name, :string
    field :street, :string
    field :postal_code, :string
    field :city, :string
    field :vat_id, :string
    field :tax_number, :string
    field :iban, :string
    field :payment_days, :integer, default: 14

    belongs_to :user, Abakus.Users.User, type: :id

    timestamps()
  end

  @fields [:name, :street, :postal_code, :city, :vat_id, :tax_number, :iban, :payment_days]

  def changeset(settings, attrs) do
    settings
    |> cast(attrs, @fields)
    |> Party.normalize([:vat_id, :iban])
    |> validate_required([:payment_days])
    |> validate_number(:payment_days, greater_than_or_equal_to: 0, less_than_or_equal_to: 365)
    |> Party.validate_vat_id()
    |> validate_iban()
  end

  @doc "Whether invoices can name this sender: name, address, IBAN, and a tax number or VAT id."
  def complete?(%__MODULE__{} = settings) do
    Enum.all?(
      [settings.name, settings.street, settings.postal_code, settings.city, settings.iban],
      &present?/1
    ) and
      (present?(settings.tax_number) or present?(settings.vat_id))
  end

  def complete?(nil), do: false

  defp present?(value), do: value not in [nil, ""]

  defp validate_iban(changeset) do
    validate_change(changeset, :iban, fn :iban, iban ->
      if valid_iban?(iban), do: [], else: [iban: "ist keine gültige IBAN"]
    end)
  end

  defp valid_iban?(iban) do
    with true <- Regex.match?(~r/^[A-Z]{2}\d{2}[A-Z0-9]{11,30}$/, iban),
         <<head::binary-size(4), rest::binary>> = iban,
         digits = for(<<char <- rest <> head>>, into: "", do: iban_digit(char)),
         {number, ""} <- Integer.parse(digits) do
      rem(number, 97) == 1
    else
      _invalid -> false
    end
  end

  defp iban_digit(char) when char in ?0..?9, do: <<char>>
  defp iban_digit(char), do: Integer.to_string(char - ?A + 10)
end
