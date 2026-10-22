defmodule Abakus.Depot.Allocation.ClassificationsTest do
  use ExUnit.Case, async: true

  import Abakus.Depot.PortfoliosFixtures, only: [money: 1]

  alias Abakus.Depot.Allocation.Classifications
  alias Abakus.Depot.Securities.Security
  alias Abakus.Depot.Taxonomies.{Assignment, Classification, Taxonomy}
  alias Abakus.Ledger.Account

  # `{id, parent_id, weight, assignments}` below root 1, assignments `{:security | :account, id, weight}`.
  defp taxonomy(classifications, root_assignments \\ []) do
    rows =
      classifications
      |> Enum.with_index()
      |> Enum.map(fn {{id, parent_id, weight, assignments}, rank} ->
        classification(id, parent_id, weight, assignments, rank)
      end)

    %Taxonomy{
      id: 7,
      name: "Anlageklassen",
      classifications: [classification(1, nil, 10_000, root_assignments, 0) | rows]
    }
  end

  defp classification(id, parent_id, weight, assignments, rank) do
    %Classification{
      id: id,
      parent_id: parent_id,
      name: "Kategorie #{id}",
      weight: weight,
      rank: rank,
      assignments: Enum.map(assignments, &assignment/1)
    }
  end

  defp assignment({:security, id, weight}), do: %Assignment{security_id: id, weight: weight}
  defp assignment({:account, id, weight}), do: %Assignment{account_id: id, weight: weight}

  defp holding(id, value), do: %{security: %Security{id: id}, value: money(value)}
  defp account(id, value), do: %{account: %Account{id: id}, value: money(value)}

  # Each row as {classification id, share in percent, target in percent}.
  defp rows(allocation) do
    Enum.map(allocation.classifications, fn row ->
      {row.classification.id, percent(row.share), percent(row.target)}
    end)
  end

  defp percent(fraction), do: fraction |> Decimal.mult(100) |> Decimal.to_float()

  describe "of/3" do
    test "compares the value below each top-level classification with its target" do
      taxonomy =
        taxonomy([
          {2, 1, 9_000, []},
          {3, 2, 8_500, [{:security, 10, 10_000}]},
          {4, 2, 1_500, [{:security, 11, 10_000}]},
          {5, 1, 1_000, [{:account, 20, 10_000}]}
        ])

      allocation =
        Classifications.of(taxonomy, [holding(10, 7_000), holding(11, 1_000)], [
          account(20, 2_000)
        ])

      assert allocation.taxonomy == taxonomy
      assert rows(allocation) == [{2, 80.0, 90.0}, {5, 20.0, 10.0}]
      assert allocation.unassigned == nil
    end

    test "counts the assignments at every level below a top-level classification" do
      taxonomy =
        taxonomy([
          {2, 1, 5_000, [{:security, 10, 10_000}]},
          {3, 2, 10_000, []},
          {4, 3, 10_000, [{:security, 11, 10_000}]},
          {5, 1, 5_000, [{:security, 12, 10_000}]}
        ])

      holdings = [holding(10, 300), holding(11, 700), holding(12, 3_000)]

      assert rows(Classifications.of(taxonomy, holdings, [])) == [
               {2, 25.0, 50.0},
               {5, 75.0, 50.0}
             ]
    end

    test "splits a holding by the weights of its assignments" do
      taxonomy =
        taxonomy([
          {2, 1, 5_000, [{:security, 10, 6_000}]},
          {3, 1, 5_000, [{:security, 10, 4_000}]}
        ])

      assert rows(Classifications.of(taxonomy, [holding(10, 1_000)], [])) ==
               [{2, 60.0, 50.0}, {3, 40.0, 50.0}]
    end

    test "adds up a security held in several portfolios" do
      taxonomy =
        taxonomy([
          {2, 1, 5_000, [{:security, 10, 10_000}]},
          {3, 1, 5_000, [{:account, 20, 10_000}]}
        ])

      allocation =
        Classifications.of(taxonomy, [holding(10, 1_000), holding(10, 2_000)], [
          account(20, 1_000)
        ])

      assert rows(allocation) == [{2, 75.0, 50.0}, {3, 25.0, 50.0}]
    end

    test "shares the value in the classifications; the rest is unassigned, of the whole value" do
      taxonomy = taxonomy([{2, 1, 10_000, [{:security, 10, 7_500}]}])

      allocation = Classifications.of(taxonomy, [holding(10, 1_000)], [account(20, 1_000)])

      assert rows(allocation) == [{2, 100.0, 100.0}]
      assert allocation.unassigned.value == money(1_250)
      assert percent(allocation.unassigned.share) == 62.5
    end

    test "counts an assignment to the root as unassigned, as PP leaves it out of the targets" do
      taxonomy = taxonomy([{2, 1, 10_000, [{:security, 10, 10_000}]}], [{:security, 11, 10_000}])

      allocation = Classifications.of(taxonomy, [holding(10, 3_000), holding(11, 1_000)], [])

      assert rows(allocation) == [{2, 100.0, 100.0}]
      assert allocation.unassigned.value == money(1_000)
      assert percent(allocation.unassigned.share) == 25.0
    end

    test "counts a holding assigned more than once with each weight, as PP does" do
      taxonomy =
        taxonomy([
          {2, 1, 5_000, [{:security, 10, 10_000}]},
          {3, 1, 5_000, [{:security, 10, 10_000}]}
        ])

      allocation = Classifications.of(taxonomy, [holding(10, 1_000)], [])

      assert rows(allocation) == [{2, 50.0, 50.0}, {3, 50.0, 50.0}]
      assert allocation.unassigned == nil
    end

    test "keeps a classification with a target but no value, not one with neither" do
      taxonomy =
        taxonomy([
          {2, 1, 9_000, [{:security, 10, 10_000}]},
          {3, 1, 1_000, []},
          {4, 1, 0, [{:security, 11, 10_000}]},
          {5, 1, 0, []}
        ])

      allocation = Classifications.of(taxonomy, [holding(10, 1_000)], [])

      assert rows(allocation) == [{2, 100.0, 90.0}, {3, 0.0, 10.0}]
    end

    test "orders the classifications by rank, then by id" do
      taxonomy = %Taxonomy{
        classifications: [
          classification(3, 1, 3_000, [], 1),
          classification(1, nil, 10_000, [], 0),
          classification(4, 1, 3_000, [], 0),
          classification(2, 1, 4_000, [{:security, 10, 10_000}], 1)
        ]
      }

      allocation = Classifications.of(taxonomy, [holding(10, 1_000)], [])

      assert Enum.map(allocation.classifications, & &1.classification.id) == [4, 2, 3]
    end

    test "gives odd targets as they are" do
      taxonomy =
        taxonomy([{2, 1, 40_000, [{:security, 10, 10_000}]}, {3, 1, -30_000, []}])

      assert rows(Classifications.of(taxonomy, [holding(10, 1_000)], [])) ==
               [{2, 100.0, 400.0}, {3, 0.0, -300.0}]
    end

    test "takes a negative balance off the value in the classifications" do
      taxonomy =
        taxonomy([
          {2, 1, 12_500, [{:security, 10, 10_000}]},
          {3, 1, -2_500, [{:account, 20, 10_000}]}
        ])

      allocation = Classifications.of(taxonomy, [holding(10, 10_000)], [account(20, -2_000)])

      assert rows(allocation) == [{2, 125.0, 125.0}, {3, -25.0, -25.0}]
    end

    test "has no classifications without value in them" do
      taxonomy = taxonomy([{2, 1, 10_000, [{:security, 10, 10_000}]}])

      for {holdings, accounts} <- [
            {[], []},
            {[holding(11, 1_000)], []},
            {[holding(10, 0)], []},
            {[], [account(10, 1_000)]}
          ] do
        assert Classifications.of(taxonomy, holdings, accounts).classifications == []
      end
    end

    test "has no classifications when the value in them is negative" do
      taxonomy = taxonomy([{2, 1, 10_000, [{:account, 20, 10_000}]}])

      assert Classifications.of(taxonomy, [], [account(20, -100)]).classifications == []
    end
  end

  describe "deviation" do
    # The deviation of a classification with `share` of 100 € and `target`.
    defp deviation(share, target) do
      taxonomy =
        taxonomy([
          {2, 1, target, [{:security, 10, 10_000}]},
          {3, 1, 10_000 - target, [{:security, 11, 10_000}]}
        ])

      holdings = [holding(10, share), holding(11, 100 - share)]
      [row, _other] = Classifications.of(taxonomy, holdings, []).classifications
      row.deviation
    end

    test "is nil within 5 percentage points of the target, as PP's default threshold" do
      assert deviation(50, 5_000) == nil
      assert deviation(55, 5_000) == nil
      assert deviation(45, 5_000) == nil
    end

    test "is :above or :below beyond 5 percentage points" do
      assert deviation(56, 5_000) == :above
      assert deviation(44, 5_000) == :below
    end
  end
end
