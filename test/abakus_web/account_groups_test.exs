defmodule AbakusWeb.AccountGroupsTest do
  use ExUnit.Case, async: true

  alias Abakus.Ledger.Account
  alias AbakusWeb.AccountGroups

  @giro %Account{id: 1, name: "Giro", kind: :checking}
  @cash %Account{id: 2, name: "Bar", kind: :cash}
  @depot %Account{id: 3, name: "Depot", kind: :tracking}
  @old %Account{id: 4, name: "Alt", kind: :savings, closed: true}

  @balances %{
    1 => %{balance: 10_000, cleared: 12_000, uncleared: -2_000},
    3 => %{balance: 500_000, cleared: 500_000, uncleared: 0},
    4 => %{balance: 300, cleared: 0, uncleared: 300}
  }

  test "groups open budget and tracking accounts and the closed ones, in the given order" do
    groups = AccountGroups.build([@depot, @old, @giro, @cash], @balances)

    assert Enum.map(groups, &{&1.key, &1.label, Enum.map(&1.rows, fn row -> row.account.id end)}) ==
             [
               {:budget, "Budget", [1, 2]},
               {:tracking, "Tracking", [3]},
               {:closed, "Geschlossen", [4]}
             ]
  end

  test "rows carry working and cleared balance, groups the working one; accounts without transactions have zero" do
    [budget, tracking, closed] = AccountGroups.build([@giro, @cash, @depot, @old], @balances)

    assert Enum.map(budget.rows, &{&1.balance, &1.cleared}) == [{10_000, 12_000}, {0, 0}]
    assert {budget.balance, tracking.balance, closed.balance} == {10_000, 500_000, 300}
  end

  test "leaves out empty groups" do
    assert [%{key: :tracking}] = AccountGroups.build([@depot], %{})
    assert AccountGroups.build([], %{}) == []
  end

  test "open/1 drops the closed accounts" do
    groups = AccountGroups.build([@giro, @old], @balances)

    assert [%{key: :budget}] = AccountGroups.open(groups)
  end
end
