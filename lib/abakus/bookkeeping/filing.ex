defmodule Abakus.Bookkeeping.Filing do
  @moduledoc """
  A return the owner sent to ELSTER: a quarter's Voranmeldung, a year's Umsatzsteuererklärung or EÜR. It keeps its
  period, the Kennzahlen it declared (by Kennzahl as text), ELSTER's transfer ticket and transmission protocol (a PDF),
  and when it was sent, and locks its period (`Abakus.Bookkeeping.Filings`). One `filed_elsewhere`, before Abakus,
  keeps only its period and when it was locked. One `pending` reserves its period while it is being sent and locks
  nothing.
  """

  use Abakus.Schema, uuid: true

  schema "bookkeeping_filings" do
    field :kind, Ecto.Enum, values: [:vat_quarter, :vat_year, :euer]
    field :first, :date
    field :last, :date
    field :kennzahlen, :map
    field :transfer_ticket, :string
    field :protocol, :binary
    field :sent_at, :utc_datetime_usec
    field :filed_elsewhere, :boolean, default: false
    field :pending, :boolean, default: false

    belongs_to :user, Abakus.Users.User, type: :id

    timestamps()
  end
end
