defmodule Abakus.Kasse.Expenses.ExpenseShare do
  @moduledoc """
  A person's share of an expense in euro cents, with the weight it was split by (see
  `Abakus.Kasse.Split`). The shares of an expense add up to its amount.
  """

  use Abakus.Schema

  alias Abakus.Kasse.Expenses.Expense
  alias Abakus.Kasse.Participants.Participant

  @primary_key false
  schema "kasse_expense_shares" do
    belongs_to :expense, Expense, primary_key: true
    belongs_to :participant, Participant, primary_key: true
    field :weight, :integer
    field :amount_cents, :integer
  end
end
