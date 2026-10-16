defmodule Abakus.Depot.Taxonomies.Assignment do
  @moduledoc "Puts a security or an account into a classification with a weight in 1/100 percent."
  use Abakus.Schema

  schema "depot_assignments" do
    belongs_to :classification, Abakus.Depot.Taxonomies.Classification
    belongs_to :security, Abakus.Depot.Securities.Security
    belongs_to :account, Abakus.Depot.Portfolios.Account
    field :weight, :integer
    field :rank, :integer, default: 0
  end
end
