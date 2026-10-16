defmodule Abakus.Kasse.BudgetLink.Link do
  @moduledoc """
  A participant linked to the budget, with the account fed by shared expenses their shares are booked in and the
  start date of the YNAB connection it replaced: an older expense gets a transaction only when entered later.
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
