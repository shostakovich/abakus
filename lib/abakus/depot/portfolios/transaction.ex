defmodule Abakus.Depot.Portfolios.Transaction do
  @moduledoc """
  One business event with a portfolio side, an account side or both (ADR 0013). A buy has a
  portfolio and an account; a security transfer goes from `portfolio` to `other_portfolio`, a cash
  transfer from `account` to `other_account`. Amounts in cents, shares × 10⁸. `source` says where
  it came from: a PP import replaces only its own transactions.
  """
  use Abakus.Schema

  alias Abakus.Depot.Portfolios.{Account, Portfolio, TransactionUnit}

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
    field :currency, :string
    field :ex_date, :naive_datetime
    field :note, :string
    field :source, Ecto.Enum, values: [:pp_import, :manual, :receipt]
    field :pp_uuid, :string
    field :pp_other_uuid, :string
    field :pp_source, :string

    has_many :units, TransactionUnit

    timestamps()
  end

  def types, do: @types

  @doc """
  Whether the user may edit or delete the transaction: one booked in the Depot, of a type the
  transaction form knows. The PP import's are read-only.
  """
  def editable?(%__MODULE__{source: source, type: type}),
    do:
      source != :pp_import and
        type in [
          :buy,
          :sell,
          :inbound_delivery,
          :outbound_delivery,
          :dividend,
          :deposit,
          :removal
        ]
end
