defmodule Abakus.Bookkeeping.LexofficeReceipt do
  @moduledoc """
  A receipt taken over from Lexoffice: its number, date, contact and total, its items with their category and VAT,
  its payments and its files in the user's Paperless, with amounts in cents, negative for what the business paid.
  It is attached to the business transaction that paid it (`transaction_id`), else waits for review until the owner
  attaches or dismisses it. One with an item in an Anlagevermögen category is proposed as a fixed asset until the
  owner records the asset (`fixed_asset_id`) or dismisses the proposal.
  """

  use Abakus.Schema, uuid: true

  alias Abakus.Bookkeeping.{FixedAsset, Vat}
  alias Abakus.Ledger.Transaction

  defmodule Item do
    @moduledoc """
    An item of a Lexoffice receipt: its category key, nil for one Abakus does not know, its VAT treatment, nil for
    a rate that does not fit the category, and its gross and net amount.
    """
    use Ecto.Schema

    @primary_key false
    embedded_schema do
      field :category, :string
      field :vat, Ecto.Enum, values: Vat.stored()
      field :amount, :integer
      field :net, :integer
    end
  end

  defmodule Payment do
    @moduledoc "A payment of a Lexoffice receipt: the day the bank posted it and its amount."
    use Ecto.Schema

    @primary_key false
    embedded_schema do
      field :date, :date
      field :amount, :integer
    end
  end

  schema "bookkeeping_lexoffice_receipts" do
    field :lexoffice_id, :string
    field :number, :string
    field :date, :date
    field :contact, :string
    field :total, :integer
    field :paperless_ids, {:array, :integer}
    field :dismissed, :boolean, default: false
    field :asset_dismissed, :boolean, default: false

    embeds_many :items, Item, on_replace: :delete
    embeds_many :payments, Payment, on_replace: :delete

    belongs_to :user, Abakus.Users.User, type: :id
    belongs_to :transaction, Transaction
    belongs_to :fixed_asset, FixedAsset

    timestamps()
  end

  @doc "The title of the receipt's file in Paperless, the `index`th from 0: „Beleg RE-1234“, „Beleg RE-1234 (2)“."
  def title(%{number: number, date: date}, index \\ 0) do
    title = "Beleg " <> (number || Date.to_iso8601(date))
    if index == 0, do: title, else: "#{title} (#{index + 1})"
  end
end
