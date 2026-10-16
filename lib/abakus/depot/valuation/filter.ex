defmodule Abakus.Depot.Valuation.Filter do
  @moduledoc """
  The portfolios and accounts a figure covers: all of a user's, or some of them, as PP's
  `PortfolioClientFilter` (read, not copied) selects them. A transaction across its edge counts
  as money in or out, as PP converts it:

  - A purchase from an account outside is an inbound delivery, a sale into one an outbound
    delivery; a purchase by a portfolio outside from an included account is a removal, a sale a
    deposit. Transfers across the edge are deliveries, deposits or removals in the same way.
  - A dividend, tax or fee of a security the included portfolios never held is a deposit or
    removal.
  - On the reference account of an included portfolio that is itself outside, a dividend of a
    security the portfolios held is paid out at once and a tax or fee paid in, so that it counts
    for the portfolio's performance.
  """

  alias Abakus.Depot.Portfolios.Transaction
  alias Abakus.Depot.Valuation

  defstruct portfolio_ids: :all,
            account_ids: :all,
            reference_account_ids: MapSet.new(),
            security_ids: :all

  @portfolio_types [:buy, :sell, :inbound_delivery, :outbound_delivery, :security_transfer]
  @security_credits [:dividend, :tax_refund, :fee_refund]
  @security_debits [:tax, :fee]

  @doc "All portfolios and accounts."
  def all, do: %__MODULE__{}

  @doc """
  `portfolios` and the accounts with `account_ids`; `transactions` tell which securities the
  portfolios ever held.
  """
  def new(portfolios, account_ids, transactions) do
    portfolio_ids = MapSet.new(portfolios, & &1.id)
    account_ids = MapSet.new(account_ids)

    %__MODULE__{
      portfolio_ids: portfolio_ids,
      account_ids: account_ids,
      reference_account_ids:
        for(
          %{reference_account_id: id} <- portfolios,
          id != nil and not MapSet.member?(account_ids, id),
          into: MapSet.new(),
          do: id
        ),
      security_ids:
        for(
          %Transaction{type: type, security_id: security_id} = t <- transactions,
          type in @portfolio_types and security_id != nil,
          MapSet.member?(portfolio_ids, t.portfolio_id) or
            MapSet.member?(portfolio_ids, t.other_portfolio_id),
          into: MapSet.new(),
          do: security_id
        )
    }
  end

  def portfolio?(%__MODULE__{portfolio_ids: ids}, id), do: included?(ids, id)

  def account?(%__MODULE__{account_ids: ids}, id), do: included?(ids, id)

  defp included?(_ids, nil), do: false
  defp included?(:all, _id), do: true
  defp included?(ids, id), do: MapSet.member?(ids, id)

  defp held?(%__MODULE__{security_ids: ids}, security_id), do: included?(ids, security_id)

  @doc """
  The money a transaction brings in or takes out, as `{kind, amount, currency}`: `:inbound` for a
  deposit or an inbound delivery, `:outbound` for a removal or an outbound delivery, and
  `:transfer_out` and `:transfer_in` for both sides of a transfer inside.
  """
  def flows(%__MODULE__{} = filter, %Transaction{type: type} = t), do: flows(filter, type, t)

  defp flows(filter, :deposit, t), do: crossing(false, account?(filter, t.account_id), sent(t))
  defp flows(filter, :removal, t), do: crossing(account?(filter, t.account_id), false, sent(t))

  defp flows(filter, :inbound_delivery, t),
    do: crossing(false, portfolio?(filter, t.portfolio_id), sent(t))

  defp flows(filter, :outbound_delivery, t),
    do: crossing(portfolio?(filter, t.portfolio_id), false, sent(t))

  defp flows(filter, :buy, t),
    do: crossing(account?(filter, t.account_id), portfolio?(filter, t.portfolio_id), sent(t))

  defp flows(filter, :sell, t),
    do: crossing(portfolio?(filter, t.portfolio_id), account?(filter, t.account_id), sent(t))

  defp flows(filter, :security_transfer, t),
    do: transfer(portfolio?(filter, t.portfolio_id), portfolio?(filter, t.other_portfolio_id), t)

  defp flows(filter, :cash_transfer, t),
    do: transfer(account?(filter, t.account_id), account?(filter, t.other_account_id), t)

  defp flows(filter, type, t) when type in @security_credits,
    do: security_related(filter, t, :inbound, :outbound)

  defp flows(filter, type, t) when type in @security_debits,
    do: security_related(filter, t, :outbound, :inbound)

  defp flows(_filter, _interest, _t), do: []

  defp sent(t), do: {t.amount, t.currency}

  # Something moving from one side to the other; only crossing the edge brings money in or out.
  defp crossing(true, false, {amount, currency}), do: [{:outbound, amount, currency}]
  defp crossing(false, true, {amount, currency}), do: [{:inbound, amount, currency}]
  defp crossing(_from, _to, _amount), do: []

  defp transfer(true, true, t) do
    {sent, sent_currency} = sent(t)
    {received, received_currency} = Valuation.received(t)
    [{:transfer_out, sent, sent_currency}, {:transfer_in, received, received_currency}]
  end

  defp transfer(true, false, t), do: crossing(true, false, sent(t))
  defp transfer(false, true, t), do: crossing(false, true, Valuation.received(t))
  defp transfer(false, false, _t), do: []

  @doc """
  The transaction as the filter's portfolios and accounts book it, as PP's filtered client holds
  it: none when it happens outside, one as it is or converted where it crosses the edge, or, for a
  dividend, tax or fee on the reference account outside, itself and the deposit or removal that
  settles it. A deposit or removal from a conversion has no security and no units.
  """
  def view(%__MODULE__{} = filter, %Transaction{type: type} = t), do: view(filter, type, t)

  defp view(filter, type, t) when type in [:deposit, :removal, :interest, :interest_charge],
    do: if(account?(filter, t.account_id), do: [t], else: [])

  defp view(filter, type, t) when type in [:inbound_delivery, :outbound_delivery],
    do: if(portfolio?(filter, t.portfolio_id), do: [t], else: [])

  defp view(filter, type, t) when type in [:buy, :sell] do
    case {portfolio?(filter, t.portfolio_id), account?(filter, t.account_id)} do
      {true, true} -> [t]
      {true, false} -> [%{t | type: delivery(type), account_id: nil}]
      {false, true} -> [cash(t, if(type == :buy, do: :removal, else: :deposit))]
      {false, false} -> []
    end
  end

  defp view(filter, :security_transfer, t) do
    case {portfolio?(filter, t.portfolio_id), portfolio?(filter, t.other_portfolio_id)} do
      {true, true} ->
        [t]

      {true, false} ->
        [%{t | type: :outbound_delivery, other_portfolio_id: nil}]

      {false, true} ->
        [
          %{
            t
            | type: :inbound_delivery,
              portfolio_id: t.other_portfolio_id,
              other_portfolio_id: nil
          }
        ]

      {false, false} ->
        []
    end
  end

  defp view(filter, :cash_transfer, t) do
    case {account?(filter, t.account_id), account?(filter, t.other_account_id)} do
      {true, true} ->
        [t]

      {true, false} ->
        [cash(%{t | other_account_id: nil}, :removal)]

      {false, true} ->
        {amount, currency} = Valuation.received(t)
        received = %{t | account_id: t.other_account_id, amount: amount, currency: currency}
        [cash(%{received | other_account_id: nil}, :deposit)]

      {false, false} ->
        []
    end
  end

  defp view(filter, type, t) do
    {outside_security, settlement} =
      if type in @security_credits, do: {:deposit, :removal}, else: {:removal, :deposit}

    cond do
      account?(filter, t.account_id) ->
        if t.security_id == nil or held?(filter, t.security_id),
          do: [t],
          else: [cash(t, outside_security)]

      MapSet.member?(filter.reference_account_ids, t.account_id) and held?(filter, t.security_id) ->
        [t, cash(t, settlement)]

      true ->
        []
    end
  end

  defp delivery(:buy), do: :inbound_delivery
  defp delivery(:sell), do: :outbound_delivery

  defp cash(t, type),
    do: %{t | type: type, portfolio_id: nil, security_id: nil, shares: nil, units: []}

  defp security_related(filter, t, outside_security, reference_account) do
    cond do
      account?(filter, t.account_id) ->
        if t.security_id == nil or held?(filter, t.security_id),
          do: [],
          else: [{outside_security, t.amount, t.currency}]

      MapSet.member?(filter.reference_account_ids, t.account_id) and held?(filter, t.security_id) ->
        [{reference_account, t.amount, t.currency}]

      true ->
        []
    end
  end
end
