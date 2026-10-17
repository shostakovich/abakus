defmodule Abakus.Depot.Distributions do
  @moduledoc """
  What a security paid out per share, from the user's dividend transactions: per payment date
  their gross value before taxes and fees per share, in euros as booked. Pure; amounts in euro
  cents, shares and amounts per share × 10⁸.
  """

  alias Abakus.Depot.Valuation

  @doc """
  The distributions in `transactions`, newest first, each with:

  - `date`, the payment date, and `ex_date`, the earliest one booked for it, nil without any
  - `shares` the dividends were paid for
  - `per_share`: their gross value per share in `currency`, always EUR; nil without shares
  - `gross`: their gross value

  The dividends of a day, such as those into several accounts, make one distribution. A dividend
  without shares adds to the gross value but not to the amount per share.
  """
  def of(transactions) do
    transactions
    |> Enum.filter(&(&1.type == :dividend))
    |> Enum.group_by(&NaiveDateTime.to_date(&1.date_time))
    |> Enum.map(fn {date, dividends} -> distribution(date, dividends) end)
    |> Enum.sort_by(& &1.date, {:desc, Date})
  end

  defp distribution(date, dividends) do
    with_shares = Enum.filter(dividends, &((&1.shares || 0) > 0))
    shares = Enum.sum_by(with_shares, & &1.shares)

    %{
      date: date,
      ex_date:
        dividends
        |> Enum.flat_map(&List.wrap(&1.ex_date && NaiveDateTime.to_date(&1.ex_date)))
        |> Enum.min(Date, fn -> nil end),
      shares: shares,
      per_share: per_share(Enum.sum_by(with_shares, &Valuation.gross_value/1), shares),
      currency: "EUR",
      gross: Enum.sum_by(dividends, &Valuation.gross_value/1)
    }
  end

  defp per_share(_gross, 0), do: nil

  # The amount per share × 10⁸ from cents and shares × 10⁸.
  defp per_share(gross, shares) do
    gross
    |> Decimal.mult(100_000_000_000_000)
    |> Decimal.div(shares)
    |> Decimal.round(0, :half_even)
    |> Decimal.to_integer()
  end
end
