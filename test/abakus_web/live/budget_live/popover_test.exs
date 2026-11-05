defmodule AbakusWeb.BudgetLive.PopoverTest do
  use ExUnit.Case, async: true

  alias Abakus.Budget.CategoryMonth
  alias AbakusWeb.BudgetLive.{Inspector, Popover}

  defp entry(id, name, available),
    do: %{
      category: %{id: id, name: name},
      group: %{id: "g"},
      cell: %CategoryMonth{category_id: id, available: available}
    }

  defp inspector(free, entries), do: %Inspector{free: free, categories: entries}

  describe "cover_amount/2" do
    test "takes as much as the source holds, up to the overspending" do
      lernen = entry("l", "Lernen", -4_000)

      assert Popover.cover_amount(lernen, 2_000) == 2_000
      assert Popover.cover_amount(lernen, 30_000) == 4_000
      assert Popover.cover_amount(lernen, 4_000) == 4_000
    end
  end

  describe "sources/2" do
    test "Zu verteilen first while positive, then every other category with money, the most first" do
      categories = [
        entry("l", "Lernen", -4_000),
        entry("s", "Software", 2_000),
        entry("f", "Festplatten", 0),
        entry("p", "Puffer", 30_000),
        entry("e", "Einkommenssteuer 23", 287_710),
        entry("m", "Minus", -100)
      ]

      assert Popover.sources(inspector(12_000, categories), "l") ==
               {12_000,
                [
                  {"e", "Einkommenssteuer 23", 287_710},
                  {"p", "Puffer", 30_000},
                  {"s", "Software", 2_000}
                ]}

      for free <- [0, -500] do
        assert {nil, [{"e", _, _}, {"p", _, _}, {"s", _, _}]} =
                 Popover.sources(inspector(free, categories), "l")
      end
    end
  end
end
