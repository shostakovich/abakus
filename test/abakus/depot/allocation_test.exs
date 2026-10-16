defmodule Abakus.Depot.AllocationTest do
  use ExUnit.Case, async: true

  import Abakus.Depot.PortfoliosFixtures, only: [money: 1]

  alias Abakus.Depot.Allocation
  alias Abakus.Depot.Allocation.Region
  alias Abakus.Depot.Securities.{Composition, Security}

  @fetched ~U[2026-10-08 16:00:00.000000Z]

  defp holding(id, value), do: %{security: %Security{id: id}, value: money(value)}

  defp composition(countries, sectors \\ %{}, fetched_at \\ @fetched),
    do: %Composition{countries: countries, sectors: sectors, fetched_at: fetched_at}

  defp shares(rows),
    do: Enum.map(rows, &{&1.key, &1.share |> Decimal.mult(100) |> Decimal.to_float()})

  describe "of/2" do
    test "splits each fund's value by its countries into regions" do
      allocation =
        Allocation.of([holding(1, 6_000), holding(2, 4_000)], %{
          1 => composition(%{"US" => 0.6, "JP" => 0.4}),
          2 => composition(%{"BR" => 1})
        })

      assert shares(allocation.regions) == [emerging_markets: 40.0, usa: 36.0, japan: 24.0]
    end

    test "counts a fund without composition as nil, „Ohne Angabe“, last" do
      allocation =
        Allocation.of([holding(1, 1_000), holding(2, 9_000)], %{
          1 => nil,
          2 => composition(%{"US" => 1})
        })

      assert shares(allocation.regions) == [usa: 90.0, nil: 10.0]
      assert shares(allocation.sectors) == [nil: 100.0]
    end

    test "adds up the countries of a region and a fund held in several portfolios" do
      allocation =
        Allocation.of([holding(1, 500), holding(1, 500)], %{
          1 => composition(%{"DE" => 0.25, "FR" => 0.25, "GB" => 0.2, "US" => 0.3})
        })

      assert shares(allocation.regions) == [europe: 70.0, usa: 30.0]
    end

    test "gives the sectors as DivvyDiary names them, by share" do
      allocation =
        Allocation.of([holding(1, 1_000)], %{
          1 => composition(%{}, %{"Energy" => 0.25, "Information Technology" => 0.75})
        })

      assert shares(allocation.sectors) == [{"Information Technology", 75.0}, {"Energy", 25.0}]
      assert shares(allocation.regions) == [nil: 100.0]
    end

    test "weighs a composition in proportion to its sum, so rounding and scale do not matter" do
      allocation =
        Allocation.of([holding(1, 1_000), holding(2, 1_000)], %{
          1 => composition(%{"US" => 60, "JP" => 40}),
          2 => composition(%{"US" => 0.500001, "CA" => 0.5})
        })

      assert [usa: usa, canada: canada, japan: 20.0] = shares(allocation.regions)
      assert_in_delta usa, 55.0, 0.0001
      assert_in_delta canada, 25.0, 0.0001

      total = Enum.reduce(allocation.regions, Decimal.new(0), &Decimal.add(&1.share, &2))
      assert Decimal.eq?(Decimal.round(total, 20), 1)
    end

    test "leaves out weights of zero and below" do
      allocation =
        Allocation.of([holding(1, 1_000)], %{
          1 => composition(%{"US" => 1, "JP" => 0, "BR" => -0.1})
        })

      assert shares(allocation.regions) == [usa: 100.0]

      assert shares(Allocation.of([holding(1, 1_000)], %{1 => composition(%{"US" => 0})}).regions) ==
               [nil: 100.0]
    end

    test "has no shares without value" do
      assert %{regions: [], sectors: [], as_of: nil} = Allocation.of([], %{})

      assert %{regions: [], sectors: []} =
               Allocation.of([holding(1, 0)], %{1 => composition(%{"US" => 1})})
    end

    test "is as of the oldest composition of the funds" do
      allocation =
        Allocation.of([holding(1, 1), holding(2, 1), holding(3, 1)], %{
          1 => composition(%{"US" => 1}, %{}, ~U[2026-10-09 16:00:00.000000Z]),
          2 => composition(%{"US" => 1}, %{}, @fetched),
          4 => composition(%{"US" => 1}, %{}, ~U[2026-09-01 16:00:00.000000Z])
        })

      assert allocation.as_of == @fetched
    end
  end

  describe "of_composition/1" do
    test "gives the regions and sectors of one fund, as of when it was fetched" do
      allocation =
        Allocation.of_composition(
          composition(%{"US" => 0.6, "JP" => 0.25, "BR" => 0.15}, %{"Energy" => 1})
        )

      assert shares(allocation.regions) == [usa: 60.0, japan: 25.0, emerging_markets: 15.0]
      assert shares(allocation.sectors) == [{"Energy", 100.0}]
      assert allocation.as_of == @fetched
    end

    test "counts a composition without sectors as „Ohne Angabe“" do
      assert shares(Allocation.of_composition(composition(%{"US" => 1})).sectors) == [nil: 100.0]
    end
  end

  describe "Region.of/1" do
    test "puts each developed market into its block by MSCI's classification" do
      assert Region.of("US") == :usa
      assert Region.of("CA") == :canada
      assert Region.of("JP") == :japan

      for country <- ~w(AU HK NZ SG), do: assert(Region.of(country) == :pacific_ex_japan)

      for country <- ~w(AT BE CH DE DK ES FI FR GB IE IL IT NL NO PT SE),
          do: assert(Region.of(country) == :europe)
    end

    test "counts every other country as an emerging market" do
      for country <- ~w(BR CN IN KR TW PL GR ZA VN) do
        assert Region.of(country) == :emerging_markets
      end
    end
  end
end
