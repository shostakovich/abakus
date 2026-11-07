defmodule Abakus.Bookkeeping.Filing do
  @moduledoc """
  A return the owner sent to ELSTER, for now a quarter's Voranmeldung: its period, the Kennzahlen it declared (by
  Kennzahl as text), ELSTER's transfer ticket and transmission protocol (a PDF), and when it was sent. It locks its
  period (`Abakus.Bookkeeping.Filings`).
  """

  use Abakus.Schema, uuid: true

  schema "bookkeeping_filings" do
    field :kind, Ecto.Enum, values: [:vat_quarter]
    field :first, :date
    field :last, :date
    field :kennzahlen, :map
    field :transfer_ticket, :string
    field :protocol, :binary
    field :sent_at, :utc_datetime_usec

    belongs_to :user, Abakus.Users.User, type: :id

    timestamps()
  end
end
