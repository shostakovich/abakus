defmodule Abakus.Depot.YearlyTTWRORRealFileTest do
  @moduledoc """
  Compares the year column of the monthly returns with PP's yearly dashboard (TTWROR per year) for
  the owner's real PP file:

      PP_FILE=/path/to/file.portfolio PP_YEARLY_TTWROR="2024=12,34 2025=-5,67" \\
        PP_YEARLY_TTWROR_DATE=2026-10-08 mix test --only pp_yearly_ttwror

  `PP_YEARLY_TTWROR` gives every year PP shows, in percent as PP rounds them, with a comma or a
  dot; `PP_YEARLY_TTWROR_DATE` is the day PP showed them, today when left out, as the current
  year runs up to it. The test fetches the ECB's rates, as PP converts at them. No real numbers
  end up in the repository.
  """
  use Abakus.DataCase

  import Abakus.UsersFixtures

  alias Abakus.Depot.{ExchangeRates, Portfolios, PPImport}
  alias Abakus.Depot.MarketData.ECB
  alias Abakus.LocalTime

  @moduletag :pp_yearly_ttwror
  @moduletag timeout: :infinity

  test "the year column equals PP's yearly TTWROR for every year" do
    scope = user_scope_fixture()
    expected = expected_years(System.fetch_env!("PP_YEARLY_TTWROR"))

    today =
      case System.get_env("PP_YEARLY_TTWROR_DATE") do
        nil -> LocalTime.today()
        date -> Date.from_iso8601!(date)
      end

    assert {:ok, _summary} = PPImport.run(scope, System.fetch_env!("PP_FILE"))
    [first | _] = Portfolios.list_transactions(scope)
    assert {:ok, rates} = ECB.rates(first.date_time |> NaiveDateTime.to_date() |> Date.add(-14))
    ExchangeRates.store(rates)

    actual =
      Map.new(
        Portfolios.performance(scope, :max, nil, today).monthly_returns,
        &{&1.year, &1.total |> Decimal.from_float() |> Decimal.mult(100) |> Decimal.round(2)}
      )

    assert Enum.sort(Map.keys(actual)) == Enum.sort(Map.keys(expected)),
           "Abakus has the years #{inspect(Map.keys(actual))}"

    for {year, percent} <- expected do
      assert Decimal.equal?(actual[year], percent),
             "#{year}: Abakus #{actual[year]} %, PP #{percent} %"
    end
  end

  defp expected_years(text) do
    for entry <- String.split(text, [" ", ";", "\n"], trim: true), into: %{} do
      [year, percent] = String.split(entry, "=")
      {String.to_integer(year), percent |> String.replace(",", ".") |> Decimal.new()}
    end
  end
end
