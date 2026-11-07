defmodule Abakus.Bookkeeping.Invoice do
  @moduledoc """
  An invoice the user wrote to a customer: its number, the date, the service period, its positions and VAT, and the
  sender and recipient as they were when it was written. A written invoice does not change. Its number is the year
  of its date followed by its counter, which runs on across years (`Abakus.Bookkeeping.Invoices`).

  The VAT is the invoice's: 19 or 7 % of the net amount, or reverse charge, where a business customer in another EU
  country owes it.

  An invoice taken over from Lexoffice keeps Lexoffice's amounts and its original PDF in Paperless, which stands
  for it instead of one Abakus sets; it may carry the 16 % of the second half of 2020, the day Lexoffice recorded
  its payment, or that it was voided there.
  """

  use Abakus.Schema, uuid: true

  import Ecto.Changeset

  alias Abakus.Bookkeeping.{Customer, Party, Position, Vat}

  @treatments [:rate_19, :rate_16, :rate_7, :reverse_charge]

  schema "bookkeeping_invoices" do
    field :number, :string
    field :counter, :integer
    field :date, :date
    field :service_from, :date
    field :service_to, :date
    field :due_date, :date

    field :vat, Ecto.Enum, values: Keyword.take(Vat.stored(), @treatments)

    field :net, :integer
    field :vat_amount, :integer
    field :total, :integer
    field :lexoffice_id, :string
    field :paperless_id, :integer
    field :paid_on, :date
    field :voided, :boolean, default: false

    embeds_many :positions, Position, on_replace: :delete
    embeds_one :sender, Party
    embeds_one :recipient, Party

    belongs_to :user, Abakus.Users.User, type: :id
    belongs_to :customer, Customer

    timestamps()
  end

  @doc "The VAT treatments a new invoice offers."
  def treatments, do: [:rate_19, :rate_7, :reverse_charge]

  @doc "The VAT treatments an invoice may have, with the 16 % only one from Lexoffice carries."
  def all_treatments, do: @treatments

  @doc "The rate of a treatment in percent."
  def rate(:reverse_charge), do: 0
  def rate(treatment), do: Vat.rate(treatment)

  @doc "What the owner fills in: the customer, the dates, the VAT and the positions; it adds up the amounts."
  def changeset(invoice, attrs) do
    invoice
    |> cast(attrs, [:customer_id, :date, :service_from, :service_to, :vat])
    |> cast_embed(:positions,
      with: &Position.changeset/2,
      sort_param: :positions_sort,
      drop_param: :positions_drop
    )
    |> validate_required([:customer_id, :date, :service_from, :service_to, :vat])
    |> validate_inclusion(:vat, treatments())
    |> validate_positions()
    |> validate_period()
    |> put_amounts()
  end

  defp validate_positions(changeset) do
    if get_field(changeset, :positions) == [],
      do: add_error(changeset, :positions, "Mindestens eine Position"),
      else: changeset
  end

  defp validate_period(changeset) do
    from = get_field(changeset, :service_from)
    to = get_field(changeset, :service_to)

    if from && to && Date.after?(from, to),
      do: add_error(changeset, :service_to, "liegt vor dem Beginn"),
      else: changeset
  end

  defp put_amounts(%{valid?: false} = changeset), do: changeset

  defp put_amounts(changeset) do
    amounts = amounts(get_field(changeset, :positions), get_field(changeset, :vat))
    change(changeset, net: amounts.net, vat_amount: amounts.vat, total: amounts.total)
  end

  @doc """
  An invoice from Lexoffice as it was written there: its number and counter, dates, amounts, positions, parties
  and status are given, nothing is computed.
  """
  def import_changeset(invoice, attrs) do
    invoice
    |> cast(attrs, [
      :customer_id,
      :number,
      :counter,
      :date,
      :service_from,
      :service_to,
      :due_date,
      :vat,
      :net,
      :vat_amount,
      :total,
      :lexoffice_id,
      :paperless_id,
      :paid_on,
      :voided
    ])
    |> put_embed(:positions, attrs.positions)
    |> put_embed(:sender, attrs.sender)
    |> put_embed(:recipient, attrs.recipient)
    |> validate_required([
      :customer_id,
      :number,
      :counter,
      :date,
      :service_from,
      :service_to,
      :due_date,
      :vat,
      :net,
      :vat_amount,
      :total,
      :lexoffice_id,
      :paperless_id
    ])
    |> unique_constraint(:number, name: :bookkeeping_invoices_user_id_number_index)
    |> unique_constraint(:lexoffice_id, name: :bookkeeping_invoices_user_id_lexoffice_id_index)
  end

  @doc "Whether the invoice came from Lexoffice, so its PDF is the original in Paperless."
  def imported?(%__MODULE__{paperless_id: id}), do: id != nil

  @doc "Whether Lexoffice saw the invoice paid or voided, so it takes no payment here."
  def settled?(%__MODULE__{} = invoice), do: invoice.voided or invoice.paid_on != nil

  @doc "The net amount, the VAT and the total in cents of `positions` under `treatment`."
  def amounts(positions, treatment) do
    net = Enum.sum_by(positions, &Position.net/1)
    vat = div(net * rate(treatment) * 2 + 100, 200)
    %{net: net, vat: vat, total: net + vat}
  end

  @doc "The number of the counter in a year: `2027126`."
  def number(year, counter),
    do: "#{year}#{String.pad_leading(Integer.to_string(counter), 3, "0")}"
end
