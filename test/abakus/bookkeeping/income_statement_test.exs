defmodule Abakus.Bookkeeping.IncomeStatementTest do
  use ExUnit.Case, async: true

  alias Abakus.Bookkeeping.{Category, Disposal, FixedAsset, IncomeStatement}

  test "every category's EÜR line is on the form, income among the income" do
    for %Category{euer: euer, kind: kind} <- Category.all(), euer != nil do
      lines =
        if kind == :income,
          do: IncomeStatement.income_kennzahlen(),
          else: IncomeStatement.expense_kennzahlen()

      assert euer in lines
    end
  end

  defp asset(name, purchased_on, net, useful_life, disposal \\ nil),
    do: %FixedAsset{
      name: name,
      purchased_on: purchased_on,
      net: net,
      useful_life: useful_life,
      disposal: disposal
    }

  test "lists the depreciated assets of the year with their book values" do
    sold = %Disposal{kind: :sale, date: ~D[2027-01-20], amount: 23_800, vat: :rate_19}

    assets = [
      asset("Notebook", ~D[2027-04-10], 240_000, 3),
      asset("Lastenrad", ~D[2025-03-01], 90_000, 3, sold),
      asset("Monitor", ~D[2027-04-10], 65_000, nil),
      asset("Drucker", ~D[2020-01-01], 90_000, 3),
      asset("Kamera", ~D[2028-01-05], 120_000, 3),
      asset("Tablet", ~D[2024-01-05], 120_000, 3, %{sold | date: ~D[2026-06-01]})
    ]

    assert IncomeStatement.year(2027, [], assets).assets == [
             %{
               name: "Lastenrad",
               purchased_on: ~D[2025-03-01],
               net: 90_000,
               start: 35_000,
               write_off: 2_500,
               remaining: 32_500,
               end: 0
             },
             %{
               name: "Notebook",
               purchased_on: ~D[2027-04-10],
               net: 240_000,
               start: 240_000,
               write_off: 60_000,
               remaining: 0,
               end: 180_000
             }
           ]
  end

  test "counts an asset by Kennzahl in a year" do
    notebook = asset("Notebook", ~D[2027-04-10], 240_000, 3)

    assert IncomeStatement.asset_kennzahlen(notebook, 2027) == %{130 => 60_000}
    assert IncomeStatement.asset_kennzahlen(notebook, 2031) == %{}
  end
end
