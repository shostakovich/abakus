defmodule Abakus.Depot.CostsTest do
  use ExUnit.Case, async: true

  import Abakus.Depot.PortfoliosFixtures, only: [money: 1]

  alias Abakus.Depot.Costs
  alias Abakus.Depot.Securities.Security

  defp fund(id, attributes \\ %{}),
    do: %Security{id: id, name: "Fonds #{id}", attributes: attributes}

  defp holding(security, value), do: %{security: security, value: money(value)}

  test "weighs the TERs by value and gives the costs a year in euros" do
    world = fund(1, %{"ter" => 0.002})
    em = fund(2, %{"ter" => 0.005})

    costs = Costs.of([holding(world, 8_000), holding(em, 2_000)])

    assert Decimal.equal?(costs.ter, Decimal.new("0.0026"))
    assert costs.per_year == money(26)

    assert [
             %{security: ^world, value: 800_000, per_year: 1_600},
             %{security: ^em, value: 200_000, per_year: 1_000}
           ] = costs.funds
  end

  test "lists a fund without a TER, but leaves it out of the weighted TER and the costs" do
    unknown = fund(1)

    costs = Costs.of([holding(unknown, 10_000), holding(fund(2, %{"ter" => 0.002}), 1_000)])

    assert [%{security: ^unknown, ter: nil, per_year: nil}, %{per_year: 200}] = costs.funds
    assert Decimal.equal?(costs.ter, Decimal.new("0.002"))
    assert costs.per_year == money(2)
  end

  test "has no weighted TER and no costs when no fund has a TER" do
    assert %{funds: [%{ter: nil}], ter: nil, per_year: nil} = Costs.of([holding(fund(1), 100)])
    assert %{funds: [], ter: nil, per_year: nil} = Costs.of([])
  end

  test "gives a fund in several portfolios once, with their value, and orders the funds by value" do
    world = fund(1, %{"ter" => 0.002})
    em = fund(2, %{"ter" => 0.005})

    costs = Costs.of([holding(world, 400), holding(em, 500), holding(world, 300)])

    assert [%{security: ^world, value: 70_000}, %{security: ^em, value: 50_000}] = costs.funds
  end

  test "rounds the costs of each fund to cents, and their total from the exact costs" do
    costs =
      Costs.of([
        holding(fund(1, %{"ter" => 0.0007}), 10),
        holding(fund(2, %{"ter" => 0.0007}), 10)
      ])

    assert [%{per_year: 1}, %{per_year: 1}] = costs.funds
    assert costs.per_year == 1
  end

  test "takes the fund size from its attribute" do
    assert [%{fund_size: 1_780_000_000_000}] =
             Costs.of([holding(fund(1, %{"aum" => 1_780_000_000_000}), 100)]).funds
  end
end
