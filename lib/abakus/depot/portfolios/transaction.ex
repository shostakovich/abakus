defmodule Abakus.Depot.Portfolios.Transaction do
  @moduledoc """
  One business event with a portfolio side, an account side or both (ADR 0013), its accounts the Ledger's. A buy
  has a portfolio and an account; a security transfer goes from `portfolio` to `other_portfolio`, a cash transfer
  from `account` to `other_account`. Amounts in euro cents, shares × 10⁸. `source` says where it came from: booked
  in the Depot or from a receipt.
  """
  use Abakus.Schema

  alias Abakus.Depot.Portfolios.{Portfolio, TransactionUnit}
  alias Abakus.Ledger.Account

  @types [
    :buy,
    :sell,
    :inbound_delivery,
    :outbound_delivery,
    :security_transfer,
    :cash_transfer,
    :deposit,
    :removal,
    :dividend,
    :interest,
    :interest_charge,
    :tax,
    :tax_refund,
    :fee,
    :fee_refund
  ]

  schema "depot_transactions" do
    belongs_to :user, Abakus.Users.User
    field :type, Ecto.Enum, values: @types
    field :date_time, :naive_datetime
    belongs_to :portfolio, Portfolio
    belongs_to :account, Account
    belongs_to :other_portfolio, Portfolio
    belongs_to :other_account, Account
    belongs_to :security, Abakus.Depot.Securities.Security
    field :shares, :integer
    field :amount, :integer
    field :ex_date, :naive_datetime
    field :note, :string
    field :source, Ecto.Enum, values: [:manual, :receipt]
    belongs_to :receipt, Abakus.Depot.Portfolios.Receipt

    has_many :units, TransactionUnit

    timestamps()
  end

  def types, do: @types

  @labels %{
    buy: "Kauf",
    sell: "Verkauf",
    inbound_delivery: "Einlieferung",
    outbound_delivery: "Auslieferung",
    security_transfer: "Depotwechsel",
    cash_transfer: "Umbuchung",
    deposit: "Einlage",
    removal: "Entnahme",
    dividend: "Dividende",
    interest: "Zinsen",
    interest_charge: "Zinsbelastung",
    tax: "Steuern",
    tax_refund: "Steuerrückerstattung",
    fee: "Gebühren",
    fee_refund: "Gebührenerstattung"
  }

  @doc "The German name of a type, e.g. „Depotwechsel“."
  def label(type), do: Map.fetch!(@labels, type)

  @doc "Whether the transaction form can edit the transaction: one of a type it knows. Any type can be deleted."
  def editable?(%__MODULE__{type: type}),
    do:
      type in [:buy, :sell, :inbound_delivery, :outbound_delivery, :dividend, :deposit, :removal]
end
