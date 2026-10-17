defmodule Abakus.Depot.Valuation.PurchaseValue do
  @moduledoc """
  What the shares of each holding cost by FIFO, including the fees and taxes of their purchases,
  as PP's `CostCalculation` (read, not copied) computes it. Each purchase or inbound delivery is a
  lot at its amount. A sale or outbound delivery takes the oldest lots of its
  portfolio and their cost in proportion; a transfer moves them, with their cost, to the other
  portfolio, where they stay as old as they were. Pure; amounts in cents, shares × 10⁸.
  """

  alias Abakus.Depot.Portfolios.Transaction

  @purchases [:buy, :inbound_delivery]
  @sales [:sell, :outbound_delivery]

  @doc "The purchase value on `date` of each holding as `%{{portfolio_id, security_id} => cents}`."
  def by_holding(transactions, date) do
    transactions
    |> Enum.filter(&(&1.type in [:security_transfer | @purchases ++ @sales]))
    |> Enum.reject(&Date.after?(NaiveDateTime.to_date(&1.date_time), date))
    |> Enum.sort_by(& &1.date_time, NaiveDateTime)
    |> Enum.reduce(%{}, fn t, lots ->
      Map.update(lots, t.security_id, book([], t), &book(&1, t))
    end)
    |> Enum.reduce(%{}, fn {security_id, lots}, values ->
      Enum.reduce(lots, values, fn lot, values ->
        Map.update(values, {lot.portfolio_id, security_id}, lot.cost, &(&1 + lot.cost))
      end)
    end)
  end

  # The lots of one security, oldest first, as `%{portfolio_id, shares, cost}`.
  defp book(lots, %Transaction{type: type} = t) when type in @purchases,
    do: lots ++ [%{portfolio_id: t.portfolio_id, shares: t.shares, cost: t.amount}]

  defp book(lots, %Transaction{type: type} = t) when type in @sales,
    do: take(lots, t.portfolio_id, t.shares)

  defp book(lots, %Transaction{type: :security_transfer} = t),
    do: move(lots, t.portfolio_id, t.other_portfolio_id, t.shares)

  # What is sold beyond the shares held is ignored, as in PP. Sold lots stay, empty and at no cost.
  defp take(lots, _portfolio_id, 0), do: lots
  defp take([], _portfolio_id, _shares), do: []

  defp take([%{portfolio_id: portfolio_id, shares: held} = lot | lots], portfolio_id, shares)
       when held > 0 do
    sold = min(shares, held)
    cost = lot.cost - cost_of(lot, sold)
    [%{lot | shares: held - sold, cost: cost} | take(lots, portfolio_id, shares - sold)]
  end

  defp take([lot | lots], portfolio_id, shares), do: [lot | take(lots, portfolio_id, shares)]

  defp move(lots, _from, _to, 0), do: lots
  defp move([], _from, _to, _shares), do: []

  defp move([%{portfolio_id: from, shares: held} = lot | lots], from, to, shares)
       when held > 0 and held <= shares,
       do: [%{lot | portfolio_id: to} | move(lots, from, to, shares - held)]

  defp move([%{portfolio_id: from, shares: held} = lot | lots], from, to, shares)
       when held > 0 do
    cost = cost_of(lot, shares)
    kept = %{lot | shares: held - shares, cost: lot.cost - cost}
    [kept, %{portfolio_id: to, shares: shares, cost: cost} | lots]
  end

  defp move([lot | lots], from, to, shares), do: [lot | move(lots, from, to, shares)]

  # The part of a lot's cost that `shares` of it carry, rounded in floating point as PP does.
  defp cost_of(%{shares: held, cost: cost}, shares), do: round(shares / held * cost)
end
