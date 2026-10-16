defmodule Abakus.Depot.BudgetLink.LinkedTransaction do
  @moduledoc """
  The budget transaction a Depot transaction is booked as, with the account, amount, date and payee the Depot wrote
  last: only what the Depot changes since is written again. Its Depot transaction is nil once deleted.
  """

  use Abakus.Schema

  alias Abakus.Ledger.{Account, Payee, Transaction}

  schema "depot_linked_transactions" do
    belongs_to :user, Abakus.Users.User
    belongs_to :depot_transaction, Abakus.Depot.Portfolios.Transaction
    belongs_to :transaction, Transaction
    belongs_to :written_account, Account
    field :written_amount, :integer
    field :written_date, :date
    belongs_to :written_payee, Payee

    timestamps()
  end
end
