defmodule Abakus.Bookkeeping.InvoicePayments do
  @moduledoc """
  Whether the user's invoices are paid: an invoice is paid once the owner confirms an incoming transaction as its
  payment (`Abakus.Bookkeeping.InvoicePayment`), and open while it has none or that transaction has left the
  register. An invoice from Lexoffice that was paid or voided there is so here too, and takes no payment.

  Proposed as an open invoice's payment are the business accounts' transactions of exactly its total, dated on or
  after it, that are no transfer and pay no other invoice, the earliest first.
  """

  import Ecto.Query
  import Abakus.Owned

  alias Abakus.{Bookkeeping, Ids, Ledger, Repo}
  alias Abakus.Bookkeeping.{Invoice, InvoicePayment, Invoices}
  alias Abakus.Users.Scope

  @doc "The transactions that paid those of `invoices` that are paid, with their payees, by invoice id."
  def payments(%Scope{} = scope, invoices) do
    by_transaction =
      Repo.all(
        from p in owned(InvoicePayment, scope),
          where: fragment("? IN (SELECT value FROM json_each(?))", p.invoice_id, ^ids(invoices)),
          select: {p.transaction_id, p.invoice_id}
      )
      |> Map.new()

    Repo.all(
      from t in Ledger.in_register(scope),
        where:
          fragment(
            "? IN (SELECT value FROM json_each(?))",
            t.id,
            ^JSON.encode!(Map.keys(by_transaction))
          ),
        preload: :payee
    )
    |> Map.new(&{by_transaction[&1.id], &1})
  end

  @doc "The transactions proposed as the payment of the open ones of `invoices`, with their payees, by invoice id."
  def proposals(%Scope{} = scope, invoices) do
    paid = payments(scope, invoices)

    case Enum.reject(invoices, &(Map.has_key?(paid, &1.id) or Invoice.settled?(&1))) do
      [] -> %{}
      open -> propose(scope, open)
    end
  end

  defp propose(scope, invoices) do
    candidates =
      Repo.all(
        from t in candidates(scope),
          where: t.amount in ^Enum.map(invoices, & &1.total),
          where: t.date >= ^Enum.min_by(invoices, & &1.date, Date).date,
          order_by: [asc: t.date, asc: t.id],
          preload: :payee
      )

    for invoice <- invoices,
        matching = Enum.filter(candidates, &proposal?(&1, invoice)),
        matching != [],
        into: %{},
        do: {invoice.id, matching}
  end

  defp candidates(scope) do
    from t in Bookkeeping.business_transactions(scope),
      where: t.amount > 0,
      where: is_nil(t.transfer_transaction_id) and is_nil(t.transfer_subtransaction_id),
      where:
        t.id not in subquery(from p in owned(InvoicePayment, scope), select: p.transaction_id)
  end

  defp proposal?(transaction, %Invoice{} = invoice),
    do:
      transaction.amount == invoice.total and Date.compare(transaction.date, invoice.date) != :lt

  @doc """
  Confirms the transaction with `transaction_id` as the payment of the user's open invoice, which is then paid.
  `{:error, :paid}` when the invoice is paid already, `{:error, :voided}` when it was voided, `{:error, :not_found}`
  when the transaction is no proposal for it.
  """
  def confirm(%Scope{} = scope, %Invoice{id: invoice_id}, transaction_id) do
    Repo.transact(fn ->
      with %Invoice{} = invoice <- Invoices.get_invoice(scope, invoice_id),
           :open <- status(scope, invoice),
           {:ok, transaction} <- proposal(scope, invoice, transaction_id) do
        Repo.delete_all(
          from p in owned(InvoicePayment, scope), where: p.invoice_id == ^invoice.id
        )

        Repo.insert(%InvoicePayment{
          user_id: user_id(scope),
          invoice_id: invoice.id,
          transaction_id: transaction.id
        })
      else
        nil -> {:error, :not_found}
        :paid -> {:error, :paid}
        :voided -> {:error, :voided}
        :error -> {:error, :not_found}
      end
    end)
  end

  defp status(_scope, %Invoice{voided: true}), do: :voided
  defp status(_scope, %Invoice{paid_on: %Date{}}), do: :paid

  defp status(scope, invoice),
    do: if(Map.has_key?(payments(scope, [invoice]), invoice.id), do: :paid, else: :open)

  defp proposal(scope, invoice, transaction_id) do
    with {:ok, id} <- Ids.cast(transaction_id),
         %{} = transaction <- Repo.one(from t in candidates(scope), where: t.id == ^id),
         true <- proposal?(transaction, invoice) do
      {:ok, transaction}
    else
      _none -> :error
    end
  end

  @doc "Removes the payment of the user's invoice, which is open again; the transaction stays."
  def release(%Scope{} = scope, %Invoice{id: id}) do
    Repo.delete_all(from p in owned(InvoicePayment, scope), where: p.invoice_id == ^id)
    :ok
  end

  defp ids(records), do: records |> Enum.map(& &1.id) |> JSON.encode!()
end
