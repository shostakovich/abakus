defmodule Abakus.Depot.Portfolios.SavingsPlan do
  @moduledoc """
  A recurring purchase, deposit, removal or interest payment. `interval` below 100 counts months,
  above 100 weeks (minus 100), as in PP. Shown only; the Depot generates nothing from it yet.
  """
  use Abakus.Schema

  schema "depot_savings_plans" do
    belongs_to :user, Abakus.Users.User
    field :name, :string
    field :note, :string
    field :type, Ecto.Enum, values: [:purchase_or_delivery, :deposit, :removal, :interest]
    belongs_to :security, Abakus.Depot.Securities.Security
    belongs_to :portfolio, Abakus.Depot.Portfolios.Portfolio
    belongs_to :account, Abakus.Depot.Portfolios.Account
    field :auto_generate, :boolean, default: false
    field :start, :date
    field :interval, :integer
    field :amount, :integer
    field :fees, :integer, default: 0
    field :taxes, :integer, default: 0
    field :attributes, :map, default: %{}

    many_to_many :transactions, Abakus.Depot.Portfolios.Transaction,
      join_through: "depot_savings_plan_transactions"

    timestamps()
  end
end
