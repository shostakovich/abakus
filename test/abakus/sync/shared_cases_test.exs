defmodule Abakus.Sync.SharedCasesTest do
  @moduledoc """
  Runs the shared cases of `sync/cases/`: the setup's messages, then each device's in every order, must give the
  rows and the budget figures the case expects.
  """

  use Abakus.DataCase

  import Abakus.DomainFixtures

  alias Abakus.{Budget, Categories, Sync}
  alias Abakus.Sync.Tables

  setup do: fix_now(~U[2026-11-02 11:00:00Z])

  @cases Path.wildcard(Path.expand("../../../sync/cases/*.json", __DIR__))

  for path <- @cases do
    @external_resource path
    shared = path |> File.read!() |> JSON.decode!()

    orders =
      case Map.keys(shared["devices"]) do
        [one, other] -> [[one, other], [other, one]]
        devices -> [devices]
      end

    for order <- orders do
      @shared shared
      @order order

      test "#{shared["name"]}, #{Enum.join(order, " before ")}" do
        scope = budget_scope()
        push(scope, "setup", @shared["setup"])
        for device <- @order, do: push(scope, device, @shared["devices"][device])

        assert_rows(@shared["rows"])
        assert_budget(scope, @shared["budget"])
      end
    end
  end

  defp push(scope, device, messages),
    do: assert({:ok, _stored} = Sync.apply_messages(scope, device, messages))

  defp assert_rows(rows) do
    for {table, by_id} <- rows, {id, expected} <- by_id do
      schema = Tables.schema(table)
      row = Repo.get!(schema, id)

      for {column, value} <- expected do
        assert Tables.encode(Map.fetch!(row, String.to_existing_atom(column))) == value,
               "#{table}.#{column} of #{id}"
      end
    end
  end

  defp assert_budget(scope, budget) do
    months = scope |> Categories.budget() |> Budget.months(~D[2026-11-01])

    for {month, categories} <- budget, {category_id, expected} <- categories do
      shown = Enum.find(months, &(Date.to_iso8601(&1.month) == month))
      row = Enum.find(shown.categories, &(&1.category_id == category_id))

      for {figure, amount} <- expected do
        assert Map.fetch!(row, String.to_existing_atom(figure)) == amount,
               "#{figure} of #{category_id} in #{month}"
      end
    end
  end
end
