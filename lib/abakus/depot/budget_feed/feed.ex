defmodule Abakus.Depot.BudgetFeed.Feed do
  @moduledoc "A portfolio or a Verrechnungskonto whose value goes into a tracking account of the budget."
  use Abakus.Schema

  schema "depot_budget_feeds" do
    belongs_to :account, Abakus.Ledger.Account
    belongs_to :portfolio, Abakus.Depot.Portfolios.Portfolio
    belongs_to :depot_account, Abakus.Depot.Portfolios.Account

    timestamps()
  end
end
