defmodule Abakus.Depot.Portfolios.Account do
  @moduledoc """
  A cash account in one currency; it exists on its own, not as part of a portfolio. Its role, see `role/1`, says
  what it is in Finanzen (`Abakus.Depot.AccountRoles`).
  """
  use Abakus.Schema

  import Ecto.Changeset

  schema "depot_accounts" do
    belongs_to :user, Abakus.Users.User
    belongs_to :budget_account, Abakus.Ledger.Account
    belongs_to :cash_of_portfolio, Abakus.Depot.Portfolios.Portfolio
    field :no_role, :boolean, default: false
    field :name, :string
    field :currency, :string
    field :note, :string
    field :retired, :boolean, default: false
    field :attributes, :map, default: %{}

    timestamps()
  end

  @doc """
  The account's role: `{:budget_account, id}` when it is that budget account, `{:portfolio_cash, id}` when it is
  that portfolio's cash, `:none` when the user chose none, nil while it has none set.
  """
  def role(%__MODULE__{budget_account_id: id}) when id != nil, do: {:budget_account, id}
  def role(%__MODULE__{cash_of_portfolio_id: id}) when id != nil, do: {:portfolio_cash, id}
  def role(%__MODULE__{no_role: true}), do: :none
  def role(%__MODULE__{}), do: nil

  @doc "A changeset setting `role`, as `role/1` gives it; any other role it had goes."
  def role_changeset(account, role) do
    {budget_account_id, cash_of_portfolio_id, no_role} =
      case role do
        {:budget_account, id} -> {id, nil, false}
        {:portfolio_cash, id} -> {nil, id, false}
        :none -> {nil, nil, true}
      end

    account
    |> change(
      budget_account_id: budget_account_id,
      cash_of_portfolio_id: cash_of_portfolio_id,
      no_role: no_role
    )
    |> unique_constraint(:budget_account_id,
      message: "ist schon die Rolle eines anderen Verrechnungskontos"
    )
  end
end
