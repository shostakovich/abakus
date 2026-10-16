defmodule Abakus.Depot.Portfolios.Receipt do
  @moduledoc """
  A bank's PDF for a transaction. The file is stored once, named by its SHA-256, in the receipts
  directory next to the database; a user's transactions with the same file share one record.

  An uploaded receipt waits in the inbox: `:recognising` while the model reads its `text`, then
  `:ready` with the recognised `fields` and the `checks`, or `:unsupported`; once confirmed it is
  `:booked`, or `:discarded`. A receipt attached in the transaction form is booked at once. One
  from Paperless keeps the document's `paperless_id` as a reference and Paperless' text.
  """
  use Abakus.Schema

  alias Abakus.Depot.Receipts.{Check, Fields}

  @inbox [:recognising, :ready, :unsupported]

  schema "depot_receipts" do
    belongs_to :user, Abakus.Users.User
    field :sha256, :string
    field :filename, :string
    field :byte_size, :integer

    field :status, Ecto.Enum,
      values: [:recognising, :ready, :unsupported, :booked, :discarded],
      default: :booked

    field :text, :string
    embeds_one :fields, Fields, on_replace: :update
    embeds_many :checks, Check, on_replace: :delete
    field :bank_reference, :string
    field :paperless_id, :integer

    timestamps()
  end

  @doc "The statuses of a receipt in the inbox."
  def inbox_statuses, do: @inbox

  @doc """
  A bank reference as stored and compared: its letters and digits in upper case, so that
  „SP-0001“ and „sp 0001“ are the same; nil without any.
  """
  def bank_reference(nil), do: nil

  def bank_reference(reference) do
    case reference |> String.replace(~r/[^[:alnum:]]/u, "") |> String.upcase() do
      "" -> nil
      normalised -> normalised
    end
  end
end
