defmodule Abakus.Depot.Valuation.Holding do
  @moduledoc """
  The shares × 10⁸ of one security in one portfolio on a date, with the `last` transaction that
  moved them. Net worth uses joint holdings over all portfolios, without a `portfolio_id`.
  """

  @enforce_keys [:security_id, :shares]
  defstruct [:portfolio_id, :security_id, :shares, :last]
end
