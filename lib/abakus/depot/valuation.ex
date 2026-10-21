defmodule Abakus.Depot.Valuation do
  @moduledoc """
  Holdings, account balances, net worth, invested capital and gross dividends, computed from
  transactions and a `Market` on every request (ADR 0014). Pure, without the database, and
  computed as PP does so that the figures match PP's. Amounts in euro cents, shares and prices
  × 10⁸.
  """

  alias Abakus.Depot.Portfolios.Transaction
  alias Abakus.Depot.Valuation.{Filter, Holding, Market}

  @credits [:deposit, :sell, :dividend, :interest, :tax_refund, :fee_refund]
  @debits [:removal, :buy, :interest_charge, :tax, :fee]
  @purchases [:buy, :inbound_delivery]

  # PP multiplies shares and price to ten significant digits.
  @pp_math %Decimal.Context{precision: 10, rounding: :half_up}

  @doc "The holdings on `date` per portfolio and security; holdings without shares are left out."
  def holdings(transactions, date), do: transactions |> share_movements(date) |> to_holdings()

  defp to_holdings(movements) do
    movements
    |> Enum.group_by(fn {portfolio_id, _shares, t} -> {portfolio_id, t.security_id} end)
    |> Enum.map(fn {{portfolio_id, security_id}, movements} ->
      %Holding{
        portfolio_id: portfolio_id,
        security_id: security_id,
        shares: Enum.sum_by(movements, &elem(&1, 1)),
        last: movements |> Enum.map(&elem(&1, 2)) |> Enum.reduce(&latest(&2, &1))
      }
    end)
    |> Enum.reject(&(&1.shares == 0))
  end

  # `{portfolio_id, shares, transaction}` for every change of shares up to `date`.
  defp share_movements(transactions, date) do
    for t <- transactions, on_or_before?(t, date), {portfolio_id, shares} <- shares_moved(t) do
      {portfolio_id, shares, t}
    end
  end

  defp shares_moved(%Transaction{type: type} = t) when type in @purchases,
    do: [{t.portfolio_id, t.shares}]

  defp shares_moved(%Transaction{type: type} = t) when type in [:sell, :outbound_delivery],
    do: [{t.portfolio_id, -t.shares}]

  defp shares_moved(%Transaction{type: :security_transfer} = t),
    do: [{t.portfolio_id, -t.shares}, {t.other_portfolio_id, t.shares}]

  defp shares_moved(_transaction), do: []

  @doc "The balance of each account on `date`."
  def balances(transactions, date) do
    for t <- transactions, on_or_before?(t, date), reduce: %{} do
      balances -> add(balances, cash_moved(t))
    end
  end

  @doc "The money a transaction moves on its accounts, as `[{account_id, cents}]`, a cash transfer's source first."
  def cash_moved(%Transaction{account_id: nil}), do: []

  def cash_moved(%Transaction{type: type} = t) when type in @credits,
    do: [{t.account_id, t.amount}]

  def cash_moved(%Transaction{type: type} = t) when type in @debits,
    do: [{t.account_id, -t.amount}]

  def cash_moved(%Transaction{type: :cash_transfer} = t),
    do: [{t.account_id, -t.amount}, {t.other_account_id, t.amount}]

  def cash_moved(_transaction), do: []

  defp on_or_before?(%Transaction{date_time: date_time}, date),
    do: not Date.after?(NaiveDateTime.to_date(date_time), date)

  defp add(totals, amounts) do
    Enum.reduce(amounts, totals, fn {key, amount}, totals ->
      Map.update(totals, key, amount, &(&1 + amount))
    end)
  end

  @doc """
  The value of a holding on `date`, in euro cents. Without any price, PP takes the gross price per
  share of the holding's last transaction, which is known only for a security in euros.
  """
  def value(%Holding{} = holding, %Market{} = market, date) do
    currency = Market.currency(market, holding.security_id)
    Market.to_euros(market, value_in_currency(holding, market, date), currency, date)
  end

  @doc "The value of a holding on `date`, in cents of the security's currency."
  def value_in_currency(%Holding{} = holding, %Market{} = market, date),
    do: amount(holding.shares, price(holding, market, date) || 0)

  @doc """
  The price per share × 10⁸ a holding is valued at on `date`, in the security's currency; nil
  without any price, unless the last transaction gives one for a security in euros.
  """
  def price(%Holding{} = holding, %Market{} = market, date) do
    case Market.price(market, holding.security_id, date) do
      # PP takes a price of 0 as none.
      price when price in [nil, 0] ->
        last_price(holding, Market.currency(market, holding.security_id))

      price ->
        price
    end
  end

  # Shares × price in cents of the security's currency, as PP rounds it.
  defp amount(shares, price) do
    shares = Decimal.div(shares, 100_000_000)

    @pp_math
    |> Decimal.Context.with(fn -> Decimal.mult(shares, price) end)
    |> Decimal.div(1_000_000)
    |> Decimal.round(0, :half_up)
    |> Decimal.to_integer()
  end

  defp last_price(%Holding{last: %Transaction{} = last}, "EUR"), do: price_per_share(last)
  defp last_price(%Holding{}, _currency), do: nil

  @doc """
  The price per share × 10⁸ in euros of a purchase, sale or delivery, before fees and taxes, as PP
  rounds it; nil without shares.
  """
  def price_per_share(%Transaction{shares: shares} = t) when is_integer(shares) and shares > 0 do
    @pp_math
    |> Decimal.Context.with(fn -> Decimal.div(gross_value(t) * 100_000_000_000_000, shares) end)
    |> Decimal.round(0, :half_even)
    |> Decimal.to_integer()
  end

  def price_per_share(%Transaction{}), do: nil

  @doc """
  The gross value of a transaction in euro cents, before fees and taxes: a purchase's amount
  without them, any other's with them added back.
  """
  def gross_value(%Transaction{} = t) do
    fees_and_taxes =
      t.units |> Enum.filter(&(&1.type in [:fee, :tax])) |> Enum.sum_by(& &1.amount)

    if t.type in @purchases, do: t.amount - fees_and_taxes, else: t.amount + fees_and_taxes
  end

  # The transactions up to a day, added up: the balance per account, the shares and the last
  # transaction that moved them per security over the portfolios, and invested capital.
  @empty_ledger %{balances: %{}, shares: %{}, last: %{}, invested_capital: 0}

  @doc """
  Net worth and invested capital on each of `dates`, in euro cents and in order of date, from one
  pass over the transactions. With a `filter`, net worth is the value of its portfolios and
  accounts, and invested capital the money its edge brought in or took out.
  """
  def history(transactions, %Market{} = market, dates, filter \\ Filter.all()) do
    transactions = Enum.sort_by(transactions, & &1.date_time, NaiveDateTime)

    dates
    |> Enum.sort(Date)
    |> Enum.map_reduce({transactions, @empty_ledger}, fn date, {pending, ledger} ->
      {due, pending} = Enum.split_while(pending, &on_or_before?(&1, date))
      ledger = Enum.reduce(due, ledger, &book(&2, &1, filter))

      point = %{
        date: date,
        net_worth: net_worth(ledger, market, date),
        invested_capital: ledger.invested_capital
      }

      {point, {pending, ledger}}
    end)
    |> elem(0)
  end

  defp book(ledger, %Transaction{} = t, filter) do
    ledger = %{
      ledger
      | balances: add(ledger.balances, inside(cash_moved(t), &Filter.account?(filter, &1))),
        invested_capital: ledger.invested_capital + transferals(filter, t)
    }

    case inside(shares_moved(t), &Filter.portfolio?(filter, &1)) do
      [] ->
        ledger

      moved ->
        shares = Enum.sum_by(moved, &elem(&1, 1))

        %{
          ledger
          | shares: add(ledger.shares, [{t.security_id, shares}]),
            last: Map.update(ledger.last, t.security_id, t, &latest(&1, t))
        }
    end
  end

  defp inside(moved, included?), do: Enum.filter(moved, fn {id, _amount} -> included?.(id) end)

  # The later of two transactions; of two at the same time the one with the larger amount, as PP
  # orders them.
  defp latest(last, t) do
    case NaiveDateTime.compare(t.date_time, last.date_time) do
      :gt -> t
      :eq when t.amount > last.amount -> t
      _not_later -> last
    end
  end

  # PP values one joint holding per security over all portfolios; its price without any close
  # needs only the last of its transactions.
  defp net_worth(ledger, market, date) do
    balances = ledger.balances |> Map.values() |> Enum.sum()

    values =
      for {security_id, shares} <- ledger.shares, shares != 0, reduce: 0 do
        sum ->
          holding = %Holding{
            security_id: security_id,
            shares: shares,
            last: ledger.last[security_id]
          }

          sum + value(holding, market, date)
      end

    balances + values
  end

  defp transferals(filter, t) do
    for {kind, amount} <- Filter.flows(filter, t), kind in [:inbound, :outbound], reduce: 0 do
      sum -> if kind == :inbound, do: sum + amount, else: sum - amount
    end
  end

  @doc "The dividends booked on the days of `range` before taxes and fees, in euro cents."
  def gross_dividends(transactions, %Date.Range{} = range) do
    for %Transaction{type: :dividend} = t <- transactions,
        NaiveDateTime.to_date(t.date_time) in range,
        reduce: 0 do
      sum -> sum + gross_value(t)
    end
  end
end
