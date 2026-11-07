defmodule Abakus.Bookkeeping.BusinessAccount do
  @moduledoc "An account of the user's business: its transactions are the ones the inbox asks a category for."

  use Abakus.Schema, uuid: true

  schema "bookkeeping_business_accounts" do
    belongs_to :user, Abakus.Users.User, type: :id
    belongs_to :account, Abakus.Ledger.Account

    timestamps()
  end
end
