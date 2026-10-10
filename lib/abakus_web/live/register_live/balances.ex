defmodule AbakusWeb.RegisterLive.Balances do
  @moduledoc """
  The balances above the register, from `AbakusWeb.AccountGroups` rows. One account: the balance equation, cleared
  + uncleared = working. All accounts: that equation for the budget accounts, plus the tracking accounts, gives the
  total; closed accounts count on their side.
  """

  alias Abakus.Ledger.Account

  def account(row), do: equation([row])

  def all(rows) do
    {budget, tracking} = Enum.split_with(rows, &Account.budget_account?(&1.account))
    budget = equation(budget)
    tracking = working(tracking)

    %{budget: budget, tracking: tracking, total: budget.working + tracking}
  end

  defp equation(rows) do
    cleared = rows |> Enum.map(& &1.cleared) |> Enum.sum()
    working = working(rows)

    %{cleared: cleared, uncleared: working - cleared, working: working}
  end

  defp working(rows), do: rows |> Enum.map(& &1.balance) |> Enum.sum()
end
