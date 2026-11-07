defmodule Abakus.Bookkeeping.Attachment do
  @moduledoc """
  The proof of a transaction, or of one part of a split: a document in the user's Paperless, by its id there, with
  its title as it was when attached. One of the whole transaction counts for all its parts.
  """

  use Abakus.Schema, uuid: true

  alias Abakus.Ledger.{Subtransaction, Transaction}

  schema "bookkeeping_attachments" do
    field :paperless_id, :integer
    field :title, :string

    belongs_to :user, Abakus.Users.User, type: :id
    belongs_to :transaction, Transaction
    belongs_to :subtransaction, Subtransaction

    timestamps()
  end
end
