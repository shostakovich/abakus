defmodule Abakus.Kasse.BudgetLink.LinkedTransaction do
  @moduledoc """
  The transaction a linked participant's share of an expense is booked as, with the category and memo the Kasse
  wrote last: where the transaction differs from them, the register overrode that field.
  """

  use Abakus.Schema

  alias Abakus.Categories.Category
  alias Abakus.Kasse.Expenses.Expense
  alias Abakus.Kasse.Participants.Participant
  alias Abakus.Ledger.Transaction

  @primary_key false
  schema "kasse_linked_transactions" do
    belongs_to :expense, Expense, primary_key: true
    belongs_to :participant, Participant, primary_key: true
    belongs_to :transaction, Transaction
    belongs_to :written_category, Category
    field :written_memo, :string

    timestamps()
  end
end
