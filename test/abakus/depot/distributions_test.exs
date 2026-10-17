defmodule Abakus.Depot.DistributionsTest do
  use ExUnit.Case, async: true

  import Abakus.Depot.PortfoliosFixtures, only: [money: 1, shares: 1]
  import Abakus.Depot.SecuritiesFixtures, only: [price: 1]

  alias Abakus.Depot.Distributions
  alias Abakus.Depot.Portfolios.{Transaction, TransactionUnit}

  defp dividend(date, count, amount, attrs \\ []) do
    struct!(
      %Transaction{
        type: :dividend,
        date_time: NaiveDateTime.new!(date, ~T[09:00:00]),
        shares: shares(count),
        amount: money(amount),
        units: []
      },
      attrs
    )
  end

  defp unit(type, amount), do: %TransactionUnit{type: type, amount: money(amount)}

  test "gives per payment date the gross value per share, before taxes and fees" do
    dividend = dividend(~D[2026-09-30], 10, 15, units: [unit(:tax, 2.5), unit(:fee, 0.5)])

    assert Distributions.of([dividend]) == [
             %{
               date: ~D[2026-09-30],
               ex_date: nil,
               shares: shares(10),
               per_share: price(1.8),
               currency: "EUR",
               gross: money(18)
             }
           ]
  end

  test "adds up the dividends of a day, such as those into several accounts" do
    dividends = [dividend(~D[2026-09-30], 10, 18), dividend(~D[2026-09-30], 2, 3.6)]

    assert [%{shares: shares, per_share: per_share, gross: gross}] =
             Distributions.of(dividends)

    assert {shares, per_share, gross} == {shares(12), price(1.8), money(21.6)}
  end

  test "lists the newest first, each with the earliest ex-date of its day" do
    ex_date = fn date -> NaiveDateTime.new!(date, ~T[00:00:00]) end

    dividends = [
      dividend(~D[2026-03-31], 10, 10),
      dividend(~D[2026-09-30], 10, 12, ex_date: ex_date.(~D[2026-09-18])),
      dividend(~D[2026-09-30], 5, 6, ex_date: ex_date.(~D[2026-09-17])),
      dividend(~D[2026-06-30], 10, 11)
    ]

    assert dividends
           |> Distributions.of()
           |> Enum.map(&{&1.date, &1.ex_date}) == [
             {~D[2026-09-30], ~D[2026-09-17]},
             {~D[2026-06-30], nil},
             {~D[2026-03-31], nil}
           ]
  end

  test "has no amount per share without shares" do
    dividends = [
      dividend(~D[2026-09-30], 0, 4),
      dividend(~D[2026-06-30], 0, 3),
      dividend(~D[2026-06-30], 10, 5)
    ]

    assert dividends
           |> Distributions.of()
           |> Enum.map(&{&1.shares, &1.per_share, &1.gross}) == [
             {0, nil, money(4)},
             {shares(10), price(0.5), money(8)}
           ]
  end

  test "rounds the amount per share half to even at 10⁻⁸" do
    assert [%{per_share: 33_333_333}] =
             Distributions.of([dividend(~D[2026-09-30], 3, 1)])
  end

  test "counts dividends only" do
    buy = %{dividend(~D[2026-09-30], 10, 1_000) | type: :buy}

    assert Distributions.of([buy]) == []
  end
end
