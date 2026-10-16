defmodule Abakus.Depot.Distributions do
  @moduledoc """
  What a security paid out per share, from the user's dividend transactions: per payment date
  their gross value before taxes and fees per share. That is in the security's currency where the
  payment knows its gross value in it, as PP keeps it for a payment in another currency, else in
  the payment's currency. Pure; amounts in cents, shares and amounts per share × 10⁸.
  """

  alias Abakus.Depot.Portfolios.Transaction
  alias Abakus.Depot.Securities.Security
  alias Abakus.Depot.Valuation
  alias Abakus.Depot.Valuation.Market

  @doc """
  The distributions of `security` from `transactions`, newest first, each with:

  - `date`, the payment date, and `ex_date`, the earliest one booked for it, nil without any
  - `shares` the dividends were paid for
  - `per_share`: their gross value per share in `currency`, nil without shares
  - `gross`: their gross value in euro cents, each at the ECB rate of its day, as the overview
    counts dividends

  The dividends of a day, such as those into several accounts, make one distribution. A dividend
  without shares, which PP allows, adds to the gross value but not to the amount per share.
  """
  def of(%Security{currency: currency}, transactions, %Market{} = market) do
    transactions
    |> Enum.filter(&(&1.type == :dividend))
    |> Enum.map(&payment(&1, currency, market))
    |> Enum.group_by(&{&1.date, &1.currency})
    |> Enum.map(fn {{date, currency}, payments} -> distribution(date, currency, payments) end)
    |> Enum.sort_by(& &1.date, {:desc, Date})
  end

  defp payment(%Transaction{} = t, security_currency, market) do
    date = NaiveDateTime.to_date(t.date_time)
    in_own_currency = Valuation.gross_value(t, t.currency)

    {currency, gross} =
      case Valuation.gross_value(t, security_currency) do
        nil -> {t.currency, in_own_currency}
        gross -> {security_currency, gross}
      end

    %{
      date: date,
      ex_date: t.ex_date && NaiveDateTime.to_date(t.ex_date),
      shares: t.shares || 0,
      currency: currency,
      gross: gross,
      euros: Market.to_euros(market, in_own_currency, t.currency, date)
    }
  end

  defp distribution(date, currency, payments) do
    with_shares = Enum.filter(payments, &(&1.shares > 0))
    shares = Enum.sum_by(with_shares, & &1.shares)

    %{
      date: date,
      ex_date: payments |> Enum.flat_map(&List.wrap(&1.ex_date)) |> Enum.min(Date, fn -> nil end),
      shares: shares,
      per_share: per_share(Enum.sum_by(with_shares, & &1.gross), shares),
      currency: currency,
      gross: Enum.sum_by(payments, & &1.euros)
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
