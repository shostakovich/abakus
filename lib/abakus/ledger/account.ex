defmodule Abakus.Ledger.Account do
  @moduledoc """
  A place money is kept. Budget accounts (checking, savings, cash) count towards the budget; tracking accounts
  only track a value. Accounts are closed, never deleted.
  """

  use Abakus.Schema

  import Ecto.Changeset

  alias Abakus.Ledger.Payee

  @budget_kinds [:checking, :savings, :cash]

  schema "accounts" do
    field :name, :string
    field :kind, Ecto.Enum, values: @budget_kinds ++ [:tracking]

    # Another app fills the account via the API; the UI hides manual entry and file import for it.
    field :fed_by, Ecto.Enum, values: [:portfolio, :shared_expenses]
    field :closed, :boolean, default: false
    field :note, :string
    field :position, :integer, default: 0
    field :last_reconciled_at, :utc_datetime_usec

    has_one :transfer_payee, Payee, foreign_key: :transfer_account_id

    timestamps()
  end

  @doc "Whether the account is a budget account (its money belongs to the budget), not a tracking account."
  def budget_account?(%__MODULE__{kind: kind}), do: kind in @budget_kinds

  @doc "The kinds of budget accounts."
  def budget_kinds, do: @budget_kinds

  def changeset(account, attrs) do
    account
    |> cast(attrs, [:name, :kind, :fed_by, :closed, :note, :position, :last_reconciled_at])
    |> validate_required([:name, :kind])
    |> validate_number(:position, greater_than_or_equal_to: 0)
    |> validate_budget_side()
  end

  # Moving an account on or off budget would rewrite the budget's history.
  defp validate_budget_side(%{data: %{kind: nil}} = changeset), do: changeset

  defp validate_budget_side(%{data: %{kind: old_kind}} = changeset) do
    validate_change(changeset, :kind, fn :kind, new_kind ->
      if old_kind in @budget_kinds == new_kind in @budget_kinds,
        do: [],
        else: [kind: "kann nicht zwischen Budget und Tracking wechseln"]
    end)
  end
end
