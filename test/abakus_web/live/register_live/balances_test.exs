defmodule AbakusWeb.RegisterLive.BalancesTest do
  use ExUnit.Case, async: true

  alias Abakus.Ledger.Account
  alias AbakusWeb.RegisterLive.Balances

  defp row(kind, balance, cleared, closed \\ false),
    do: %{account: %Account{kind: kind, closed: closed}, balance: balance, cleared: cleared}

  describe "account/1" do
    test "cleared and uncleared add up to the working balance" do
      assert Balances.account(row(:checking, 245_001, 250_000)) ==
               %{cleared: 250_000, uncleared: -4_999, working: 245_001}
    end

    test "holds for a tracking account too" do
      assert Balances.account(row(:tracking, 1_000_000, 1_000_000)) ==
               %{cleared: 1_000_000, uncleared: 0, working: 1_000_000}
    end
  end

  describe "all/1" do
    test "budget accounts as an equation, plus tracking, make the total" do
      rows = [
        row(:checking, 245_001, 250_000),
        row(:cash, -1_250, 0),
        row(:tracking, 1_000_000, 1_000_000),
        row(:tracking, -50_000, -50_000)
      ]

      assert Balances.all(rows) == %{
               budget: %{cleared: 250_000, uncleared: -6_249, working: 243_751},
               tracking: 950_000,
               total: 1_193_751
             }
    end

    test "counts closed accounts on their side" do
      rows = [
        row(:checking, 1_000, 1_000),
        row(:savings, 300, 0, true),
        row(:tracking, 7, 7, true)
      ]

      assert %{budget: %{working: 1_300, uncleared: 300}, tracking: 7, total: 1_307} =
               Balances.all(rows)
    end

    test "is zero without accounts" do
      assert Balances.all([]) == %{
               budget: %{cleared: 0, uncleared: 0, working: 0},
               tracking: 0,
               total: 0
             }
    end
  end
end
