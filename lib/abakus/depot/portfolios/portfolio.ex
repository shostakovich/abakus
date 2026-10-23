defmodule Abakus.Depot.Portfolios.Portfolio do
  @moduledoc """
  A securities account; its purchases, sales and dividends settle against its Verrechnungskonto
  (`reference_account`), an account in the Ledger, by default. Its depot number, as the bank prints it, finds the
  portfolio of a receipt; only its digits count.
  """
  use Abakus.Schema

  import Ecto.Changeset

  schema "depot_portfolios" do
    belongs_to :user, Abakus.Users.User
    belongs_to :reference_account, Abakus.Ledger.Account
    field :name, :string
    field :note, :string
    field :retired, :boolean, default: false
    field :attributes, :map, default: %{}
    field :depot_number, :string

    timestamps()
  end

  @doc """
  A changeset for what the user edits of a portfolio: its depot number, nil for none, and its Verrechnungskonto.
  `checks` has `taken_by`, which gives the name of another portfolio of the user with a depot number's digits (nil if
  there is none), and the accounts the portfolio may use: `account_ids`, of which those in `owners` are another
  portfolio's cash (by the name of that portfolio) and those in `waiting_ids` may not newly become its cash.
  """
  def changeset(portfolio, attrs, checks) do
    portfolio
    |> cast(attrs, [:depot_number, :reference_account_id])
    |> update_change(:depot_number, &(&1 && String.trim(&1)))
    |> validate_length(:depot_number, max: 40)
    |> validate_change(:depot_number, fn :depot_number, number ->
      cond do
        digits(number) == "" -> [depot_number: "braucht Ziffern"]
        name = checks.taken_by.(digits(number)) -> [depot_number: "gehört schon zu „#{name}“"]
        true -> []
      end
    end)
    |> validate_required(:reference_account_id)
    |> validate_change(:reference_account_id, fn :reference_account_id, id ->
      cond do
        name = checks.owners[id] ->
          [reference_account_id: "ist schon das Verrechnungskonto von „#{name}“"]

        id not in checks.account_ids ->
          [reference_account_id: "ist kein offenes Konto in Finanzen"]

        id in checks.waiting_ids ->
          [reference_account_id: "hat noch unbestätigte Buchungen oder Zuordnungsvorschläge"]

        true ->
          []
      end
    end)
  end

  @doc "The digits of a depot number, which is all that counts when comparing them."
  def digits(nil), do: ""
  def digits(number), do: String.replace(number, ~r/\D/, "")
end
