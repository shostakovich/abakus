defmodule Abakus.Bookkeeping.Settings do
  @moduledoc """
  A user's bookkeeping settings: the sender their invoices name, with the tax number or VAT id an invoice must
  carry, the IBAN it is paid to and the days until it is due; the state of the tax office, which ELSTER needs with
  the tax number, and the ELSTER certificate (a .pfx file) returns are sent with. Its PIN is never stored. The EÜR
  also names the kind of business ("Art des Betriebs") and whether its income is from self-employment, as a
  freelancer's, or from a trade.
  """

  use Abakus.Schema, uuid: true

  import Ecto.Changeset

  alias Abakus.Bookkeeping.{Party, States}

  schema "bookkeeping_settings" do
    field :name, :string
    field :street, :string
    field :postal_code, :string
    field :city, :string
    field :vat_id, :string
    field :tax_number, :string
    field :iban, :string
    field :payment_days, :integer, default: 14
    field :tax_state, :string
    field :business_activity, :string
    field :income_kind, Ecto.Enum, values: [:self_employment, :trade], default: :self_employment
    field :elster_certificate, :binary, redact: true
    field :elster_certificate_name, :string

    belongs_to :user, Abakus.Users.User, type: :id

    timestamps()
  end

  @fields [
    :name,
    :street,
    :postal_code,
    :city,
    :vat_id,
    :tax_number,
    :tax_state,
    :business_activity,
    :income_kind,
    :iban,
    :payment_days
  ]

  @max_certificate_size 100_000

  def changeset(settings, attrs) do
    settings
    |> cast(attrs, @fields)
    |> Party.normalize([:vat_id, :iban])
    |> update_change(:business_activity, &(&1 && String.trim(&1)))
    |> validate_required([:payment_days, :income_kind])
    |> validate_length(:business_activity, max: 100)
    |> validate_number(:payment_days, greater_than_or_equal_to: 0, less_than_or_equal_to: 365)
    |> validate_inclusion(:tax_state, States.codes())
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

  @doc "Stores the ELSTER certificate `content` under its file name, or forgets it with `nil`."
  def certificate_changeset(settings, nil),
    do: change(settings, elster_certificate: nil, elster_certificate_name: nil)

  def certificate_changeset(settings, {content, filename}) do
    settings
    |> change(elster_certificate: content, elster_certificate_name: Path.basename(filename))
    |> validate_change(:elster_certificate, fn :elster_certificate, content ->
      if byte_size(content) in 1..@max_certificate_size,
        do: [],
        else: [elster_certificate: "ist kein ELSTER-Zertifikat"]
    end)
  end

  @doc """
  What sending a return of `kind` (`:vat` or `:euer`) to ELSTER still lacks, in the words of the settings: none when
  nothing does.
  """
  def missing_for_elster(%__MODULE__{} = settings, kind \\ :vat) do
    for {field, label} <- elster_fields(kind),
        not present?(Map.fetch!(settings, field)),
        do: label
  end

  defp elster_fields(:vat),
    do: [
      name: "Name",
      street: "Straße",
      postal_code: "PLZ",
      city: "Ort",
      tax_number: "Steuernummer",
      tax_state: "Bundesland",
      elster_certificate: "ELSTER-Zertifikat"
    ]

  defp elster_fields(:euer), do: elster_fields(:vat) ++ [business_activity: "Art des Betriebs"]

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
