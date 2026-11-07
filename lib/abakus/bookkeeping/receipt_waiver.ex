defmodule Abakus.Bookkeeping.ReceiptWaiver do
  @moduledoc "The mark that a transaction needs no receipt, such as a bank fee."

  use Abakus.Schema, uuid: true

  schema "bookkeeping_receipt_waivers" do
    belongs_to :user, Abakus.Users.User, type: :id
    belongs_to :transaction, Abakus.Ledger.Transaction

    timestamps()
  end
end
