defmodule Abakus.Depot.Valuation do
  @moduledoc """
  Holdings, account balances, net worth, invested capital and gross dividends, computed from
  transactions and a `Market` on every request (ADR 0014). Pure, without the database, and
  computed as PP does so that the figures match PP's. Amounts in cents, shares and prices × 10⁸.
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

  @doc "The balance of each account on `date`, in the account's currency."
  def balances(transactions, date) do
    for t <- transactions, on_or_before?(t, date), reduce: %{} do
      balances -> add(balances, cash_moved(t))
    end
  end

  defp cash_moved(%Transaction{account_id: nil}), do: []

  defp cash_moved(%Transaction{type: type} = t) when type in @credits,
    do: [{t.account_id, t.amount}]

  defp cash_moved(%Transaction{type: type} = t) when type in @debits,
    do: [{t.account_id, -t.amount}]

  defp cash_moved(%Transaction{type: :cash_transfer} = t),
    do: [{t.account_id, -t.amount}, {t.other_account_id, t |> received() |> elem(0)}]

  defp cash_moved(_transaction), do: []

  @doc """
  What a cash transfer credits the other account, as `{amount, currency}`: into another currency
  the converted gross value, as PP books it.
  """
  def received(%Transaction{} = t) do
    case gross_value_unit(t) do
      %{fx_amount: amount, fx_currency: currency} when is_integer(amount) -> {amount, currency}
      _same_currency -> {t.amount, t.currency}
    end
  end

  defp on_or_before?(%Transaction{date_time: date_time}, date),
    do: not Date.after?(NaiveDateTime.to_date(date_time), date)

  defp add(totals, amounts) do
    Enum.reduce(amounts, totals, fn {key, amount}, totals ->
      Map.update(totals, key, amount, &(&1 + amount))
    end)
  end

  @doc """
  The value of a holding on `date`, in euro cents. Without any price, PP takes the gross price per
  share of the holding's last transaction.
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
  without any price or transaction.
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

  defp last_price(%Holding{last: nil}, _currency), do: nil
  defp last_price(%Holding{last: last}, currency), do: price_per_share(last, currency)

  @doc """
  The price per share × 10⁸ of a purchase, sale or delivery in `currency`, before fees and taxes,
  as PP rounds it; nil when its gross value is not known in that currency.
  """
  def price_per_share(%Transaction{shares: shares} = t, currency) do
    case gross_value(t, currency) do
      gross when is_integer(gross) and shares > 0 ->
        @pp_math
        |> Decimal.Context.with(fn -> Decimal.div(gross * 100_000_000_000_000, shares) end)
        |> Decimal.round(0, :half_even)
        |> Decimal.to_integer()

      _unknown ->
        nil
    end
  end

  @doc """
  The gross value of a transaction in cents of `currency`, before fees and taxes: a purchase's
  amount without them, any other's with them added back, or in another currency the forex amount
  of its gross value unit, as PP keeps it; nil when it is not known in `currency`.
  """
  def gross_value(%Transaction{currency: currency} = t, currency) do
    fees_and_taxes =
      t.units |> Enum.filter(&(&1.type in [:fee, :tax])) |> Enum.sum_by(& &1.amount)

    if t.type in @purchases, do: t.amount - fees_and_taxes, else: t.amount + fees_and_taxes
  end

  def gross_value(t, currency) do
    case gross_value_unit(t) do
      %{fx_currency: ^currency, fx_amount: fx_amount} -> fx_amount
      _other -> nil
    end
  end

  defp gross_value_unit(t), do: Enum.find(t.units, &(&1.type == :gross_value))

  # The transactions up to a day, added up: the balance per account, the shares and the last
  # transaction that moved them per security over the portfolios, and invested capital.
  @empty_ledger %{balances: %{}, shares: %{}, last: %{}, invested_capital: 0}

  @doc """
  Net worth and invested capital on each of `dates`, in euro cents and in order of date, from one
  pass over the transactions. `accounts` give the currency of each balance. With a `filter`, net
  worth is the value of its portfolios and accounts, and invested capital the money its edge
  brought in or took out. Invested capital converts each transferal at the ECB rate of its own
  day, so `market` needs the rates from the first transaction on.
  """
  def history(transactions, accounts, %Market{} = market, dates, filter \\ Filter.all()) do
    currencies = Map.new(accounts, &{&1.id, &1.currency})
    transactions = Enum.sort_by(transactions, & &1.date_time, NaiveDateTime)

    dates
    |> Enum.sort(Date)
    |> Enum.map_reduce({transactions, @empty_ledger}, fn date, {pending, ledger} ->
      {due, pending} = Enum.split_while(pending, &on_or_before?(&1, date))
      ledger = Enum.reduce(due, ledger, &book(&2, &1, filter, market))

      point = %{
        date: date,
        net_worth: net_worth(ledger, currencies, market, date),
        invested_capital: ledger.invested_capital
      }

      {point, {pending, ledger}}
    end)
    |> elem(0)
  end

  defp book(ledger, %Transaction{} = t, filter, market) do
    ledger = %{
      ledger
      | balances: add(ledger.balances, inside(cash_moved(t), &Filter.account?(filter, &1))),
        invested_capital: ledger.invested_capital + transferals(filter, t, market)
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
  defp net_worth(ledger, currencies, market, date) do
    balances =
      Enum.sum_by(ledger.balances, fn {account_id, amount} ->
        Market.to_euros(market, amount, currencies[account_id], date)
      end)

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

  # Money from outside, in euros at the rate of its day, as PP counts invested capital.
  defp transferals(filter, t, market) do
    for {kind, amount, currency} <- Filter.flows(filter, t),
        kind in [:inbound, :outbound],
        reduce: 0 do
      sum ->
        euros = Market.to_euros(market, amount, currency, NaiveDateTime.to_date(t.date_time))
        if kind == :inbound, do: sum + euros, else: sum - euros
    end
  end

  @doc """
  The dividends booked on the days of `range` before taxes and fees, in euro cents, each at the
  ECB rate of its day, as PP's gross value of a dividend.
  """
  def gross_dividends(transactions, %Market{} = market, %Date.Range{} = range) do
    for %Transaction{type: :dividend} = t <- transactions,
        date = NaiveDateTime.to_date(t.date_time),
        date in range,
        reduce: 0 do
      sum -> sum + Market.to_euros(market, gross_value(t, t.currency), t.currency, date)
    end
  end
end
