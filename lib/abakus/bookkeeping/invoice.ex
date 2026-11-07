defmodule Abakus.Bookkeeping.Invoice do
  @moduledoc """
  An invoice the user wrote to a customer: its number, the date, the service period, its positions and VAT, and the
  sender and recipient as they were when it was written. A written invoice does not change. Its number is the year
  of its date followed by its counter, which runs on across years (`Abakus.Bookkeeping.Invoices`).

  The VAT is the invoice's: 19 or 7 % of the net amount, or reverse charge, where a business customer in another EU
  country owes it.
  """

  use Abakus.Schema, uuid: true

  import Ecto.Changeset

  alias Abakus.Bookkeeping.{Customer, Party, Position}

  @rates [rate_19: 19, rate_7: 7, reverse_charge: 0]

  schema "bookkeeping_invoices" do
    field :number, :string
    field :counter, :integer
    field :date, :date
    field :service_from, :date
    field :service_to, :date
    field :due_date, :date
    field :vat, Ecto.Enum, values: [rate_19: "19", rate_7: "7", reverse_charge: "reverse_charge"]
    field :net, :integer
    field :vat_amount, :integer
    field :total, :integer

    embeds_many :positions, Position, on_replace: :delete
    embeds_one :sender, Party
    embeds_one :recipient, Party

    belongs_to :user, Abakus.Users.User, type: :id
    belongs_to :customer, Customer

    timestamps()
  end

  @doc "The VAT treatments an invoice offers."
  def treatments, do: Keyword.keys(@rates)

  @doc "The rate of a treatment in percent."
  def rate(treatment), do: Keyword.fetch!(@rates, treatment)

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
