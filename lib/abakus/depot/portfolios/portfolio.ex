defmodule Abakus.Depot.Portfolios.Portfolio do
  @moduledoc """
  A securities account; purchases settle against its reference account by default. Its depot
  number, as the bank prints it, finds the portfolio of a receipt; only its digits count. A portfolio
  of the budget owner is its `budget_account` in the budget (`Abakus.Depot.BudgetFeed`).
  """
  use Abakus.Schema

  import Ecto.Changeset

  schema "depot_portfolios" do
    belongs_to :user, Abakus.Users.User
    belongs_to :reference_account, Abakus.Depot.Portfolios.Account
    belongs_to :budget_account, Abakus.Ledger.Account
    field :name, :string
    field :note, :string
    field :retired, :boolean, default: false
    field :attributes, :map, default: %{}
    field :depot_number, :string

    timestamps()
  end

  @doc """
  A changeset for the depot number, nil for none; `taken_by` gives the name of another portfolio
  of the user with the same digits, nil if there is none.
  """
  def depot_number_changeset(portfolio, attrs, taken_by) do
    portfolio
    |> cast(attrs, [:depot_number])
    |> update_change(:depot_number, &(&1 && String.trim(&1)))
    |> validate_length(:depot_number, max: 40)
    |> validate_change(:depot_number, fn :depot_number, number ->
      cond do
        digits(number) == "" -> [depot_number: "braucht Ziffern"]
        name = taken_by.(digits(number)) -> [depot_number: "gehört schon zu „#{name}“"]
        true -> []
      end
    end)
  end

  @doc "The digits of a depot number, which is all that counts when comparing them."
  def digits(nil), do: ""
  def digits(number), do: String.replace(number, ~r/\D/, "")
end
