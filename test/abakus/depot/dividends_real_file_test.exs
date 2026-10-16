defmodule Abakus.Depot.DividendsRealFileTest do
  @moduledoc """
  Compares the dividends per year with PP's for the owner's real PP file:

      PP_FILE=/path/to/file.portfolio PP_DIVIDENDS="2024=1.234,56; 2025=2345.67" \\
        mix test --only pp_dividends

  `PP_DIVIDENDS` gives PP's dividends per year in euros, as `123.456,78` or `123456.78`, the
  years separated by `;`. They are gross, as PP's payments view shows them by default; with
  `PP_DIVIDENDS_AMOUNT=net` they are net. The test fetches the ECB's rates from the first year
  on, as PP converts at them. No real numbers end up in the repository.
  """
  use Abakus.DataCase

  import Abakus.UsersFixtures

  alias Abakus.Depot.{Portfolios, PPImport}
  alias Abakus.ExchangeRates
  alias Abakus.ExchangeRates.ECB
  alias Abakus.LocalTime

  @moduletag :pp_dividends
  @moduletag timeout: :infinity

  test "the dividends of each year equal PP's" do
    scope = user_scope_fixture()
    expected = expected_years(System.fetch_env!("PP_DIVIDENDS"))
    amount = amount(System.get_env("PP_DIVIDENDS_AMOUNT", "gross"))

    assert {:ok, _summary} = PPImport.run(scope, System.fetch_env!("PP_FILE"))
    first_year = expected |> Map.keys() |> Enum.min()
    assert {:ok, rates} = ECB.rates(Date.new!(first_year - 1, 12, 1))
    ExchangeRates.store(rates)

    years = Portfolios.dividends(scope, nil, LocalTime.today()).years
    actual = Map.new(years, &{&1.year, &1[amount]})

    for {year, cents} <- Enum.sort(expected) do
      assert Map.get(actual, year, 0) == cents,
             "#{year}: Abakus #{Map.get(actual, year, 0)} ct, PP #{cents} ct"
    end
  end

  defp amount("gross"), do: :gross
  defp amount("net"), do: :net

  defp expected_years(text) do
    for entry <- String.split(text, ";", trim: true), into: %{} do
      [year, euros] = entry |> String.trim() |> String.split("=", parts: 2)
      {String.to_integer(String.trim(year)), cents(String.trim(euros))}
    end
  end

  defp cents(euros) do
    euros =
      if euros =~ ",",
        do: euros |> String.replace(".", "") |> String.replace(",", "."),
        else: euros

    euros |> Decimal.new() |> Decimal.mult(100) |> Decimal.to_integer()
  end
end
