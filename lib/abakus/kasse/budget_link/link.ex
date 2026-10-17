defmodule Abakus.Kasse.BudgetLink.Link do
  @moduledoc """
  A participant linked to the budget, with the account fed by shared expenses their shares are booked in and a
  start date: an expense dated before it gets a transaction only when entered or moved later; nil books all.
  """

  use Abakus.Schema

  alias Abakus.Kasse.Participants.Participant
  alias Abakus.Ledger.Account

  @primary_key false
  schema "kasse_budget_links" do
    belongs_to :participant, Participant, primary_key: true
    belongs_to :account, Account
    field :start_date, :date

    timestamps()
  end
end
