defmodule Abakus.Bookkeeping.InvoicePayment do
  @moduledoc "The incoming transaction the owner confirmed as an invoice's payment."

  use Abakus.Schema, uuid: true

  schema "bookkeeping_invoice_payments" do
    belongs_to :user, Abakus.Users.User, type: :id
    belongs_to :invoice, Abakus.Bookkeeping.Invoice
    belongs_to :transaction, Abakus.Ledger.Transaction

    timestamps()
  end
end
