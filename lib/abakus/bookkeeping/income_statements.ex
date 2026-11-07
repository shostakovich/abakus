defmodule Abakus.Bookkeeping.IncomeStatements do
  @moduledoc """
  The user's EÜR (`Abakus.Bookkeeping.IncomeStatement`) of a year, from their tax lines on any of their accounts
  (`Abakus.Bookkeeping.entries/3`) and their asset register.
  """

  alias Abakus.Bookkeeping
  alias Abakus.Bookkeeping.{FixedAssets, IncomeStatement}
  alias Abakus.Users.Scope

  @doc "The EÜR of `year`."
  def year(%Scope{} = scope, year) do
    entries = Bookkeeping.entries(scope, Date.new!(year, 1, 1), Date.new!(year, 12, 31))
    IncomeStatement.year(year, entries, FixedAssets.list(scope))
  end
end
