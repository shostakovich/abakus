defmodule Abakus.Bookkeeping.LexofficeReceipts do
  @moduledoc """
  Where the receipts taken over from Lexoffice (`Abakus.Bookkeeping.LexofficeReceipt`) go: to the business
  transaction that paid them, and, for an Anlagevermögen purchase, into the asset register.

  A receipt is matched by its payment's day and amount: one with a single payment is attached to the business
  transaction of exactly that day and amount when there is only that one and no other waiting receipt has a payment
  like it. Attaching makes its files the transaction's attachments and, when its items are of one category and VAT
  treatment, gives the transaction that tax line, unless it is split, has one already or is in a locked period. Any
  other receipt waits on the review list with its proposals until the owner attaches or dismisses it, and so does one
  whose transaction has left the register: the business transactions of a payment's amount from a week before to a
  week after it, or of its total around its date when it has no payment, the closest first. Candidates are no
  transfers, no invoice's or disposal's payment and no other receipt's transaction.

  Each receipt with a purchase in an Anlagevermögen category is proposed as a fixed asset, its net amount there
  as the purchase, until the owner records the asset or dismisses the proposal.
  """

  import Ecto.Query
  import Abakus.Owned
  import Abakus.JsonList, only: [in_json: 2]

  alias Abakus.{Bookkeeping, Ledger, Repo}

  alias Abakus.Bookkeeping.{
    Attachments,
    Category,
    FixedAsset,
    FixedAssets,
    LexofficeReceipt
  }

  alias Abakus.Ledger.Transaction
  alias Abakus.Users.Scope

  @days 7

  @doc "Attaches every waiting receipt that has exactly one match; the number attached."
  def match(%Scope{} = scope) do
    receipts = waiting(scope)
    singles = for r <- receipts, [payment] <- [r.payments], do: {r, key(payment)}
    wanted = receipts |> Enum.flat_map(& &1.payments) |> Enum.frequencies_by(&key/1)

    found =
      scope
      |> candidates(Enum.map(singles, fn {_r, {_date, amount}} -> amount end))
      |> Enum.group_by(&{&1.date, &1.amount})

    Enum.count(singles, fn {receipt, key} ->
      with 1 <- wanted[key],
           [transaction] <- found[key] || [],
           {:ok, _receipt} <- attach_to(scope, receipt, transaction) do
        true
      else
        _none -> false
      end
    end)
  end

  defp key(payment), do: {payment.date, payment.amount}

  @doc "The receipts waiting for review, the latest first, each as `{receipt, proposals}` with the payees."
  def review(%Scope{} = scope) do
    receipts = waiting(scope)
    wanted = Enum.flat_map(receipts, &wanted/1)
    transactions = candidates(scope, Enum.map(wanted, &elem(&1, 1)))

    for receipt <- Enum.sort_by(receipts, & &1.date, {:desc, Date}),
        do: {receipt, proposals(receipt, transactions)}
  end

  @doc "How many receipts wait for review."
  def review_count(%Scope{} = scope), do: Repo.aggregate(waiting_query(scope), :count)

  defp waiting(scope), do: Repo.all(from r in waiting_query(scope), order_by: [r.date, r.id])

  defp waiting_query(scope) do
    in_register = from t in Ledger.in_register(scope), select: t.id

    from r in owned(LexofficeReceipt, scope),
      where: not r.dismissed,
      where: is_nil(r.transaction_id) or r.transaction_id not in subquery(in_register)
  end

  defp wanted(%LexofficeReceipt{payments: [], date: date, total: total}), do: [{date, total}]
  defp wanted(%LexofficeReceipt{payments: payments}), do: Enum.map(payments, &key/1)

  defp proposals(receipt, transactions) do
    wanted = wanted(receipt)

    transactions
    |> Enum.flat_map(fn t ->
      distances =
        for {date, amount} <- wanted,
            t.amount == amount,
            distance = abs(Date.diff(t.date, date)),
            distance <= @days,
            do: distance

      if distances == [], do: [], else: [{Enum.min(distances), t}]
    end)
    |> Enum.sort_by(fn {distance, t} -> {distance, Date.to_gregorian_days(t.date)} end)
    |> Enum.map(&elem(&1, 1))
  end

  defp candidates(_scope, []), do: []

  defp candidates(scope, amounts) do
    Repo.all(
      from t in Bookkeeping.business_transactions(scope),
        where: in_json(t.amount, Enum.uniq(amounts)),
        where: is_nil(t.transfer_transaction_id) and is_nil(t.transfer_subtransaction_id),
        where: t.id not in subquery(Bookkeeping.claimed_transactions(scope)),
        preload: :payee
    )
  end

  @doc """
  Attaches the waiting receipt to the transaction with `transaction_id`, one of its proposals. `{:error,
  :not_found}` for a receipt no longer waiting or a transaction no longer proposed.
  """
  def attach(%Scope{} = scope, %LexofficeReceipt{id: id}, transaction_id) do
    with %LexofficeReceipt{} = receipt <-
           Repo.one(from r in waiting_query(scope), where: r.id == ^id),
         %Transaction{} = transaction <-
           Enum.find(
             proposals(receipt, candidates(scope, Enum.map(wanted(receipt), &elem(&1, 1)))),
             &(&1.id == transaction_id)
           ) do
      attach_to(scope, receipt, transaction)
    else
      _none -> {:error, :not_found}
    end
  end

  defp attach_to(scope, receipt, %Transaction{id: id}) do
    Repo.transact(fn ->
      with %Transaction{} = transaction <- Bookkeeping.get_transaction(scope, id),
           {:ok, receipt} <-
             receipt |> Ecto.Changeset.change(transaction_id: id) |> Repo.update(),
           :ok <- link_files(scope, receipt, transaction),
           :ok <- put_tax_line(scope, receipt, transaction) do
        {:ok, receipt}
      else
        nil -> {:error, :not_found}
        {:error, reason} -> {:error, reason}
      end
    end)
  end

  defp link_files(scope, receipt, transaction) do
    receipt.paperless_ids
    |> Enum.with_index()
    |> Enum.reduce_while(:ok, fn {paperless_id, index}, :ok ->
      case Attachments.link(
             scope,
             transaction,
             paperless_id,
             LexofficeReceipt.title(receipt, index)
           ) do
        {:ok, _attachment} -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp put_tax_line(scope, receipt, transaction) do
    with [%{category: category, vat: vat}] when category != nil and vat != nil <-
           Enum.uniq_by(receipt.items, &{&1.category, &1.vat}),
         true <- Bookkeeping.tax_lines(scope, [transaction]) == %{},
         {:ok, _lines} <-
           Bookkeeping.save_tax_lines(scope, transaction, %{
             Bookkeeping.side_key(nil) => %{"category" => category, "vat" => vat}
           }) do
      :ok
    else
      {:error, reason} when reason in [:locked, :pays_disposal] -> :ok
      {:error, reason} -> {:error, reason}
      _none -> :ok
    end
  end

  @doc "Dismisses the waiting receipt: it stays in Paperless and leaves the review list."
  def dismiss(%Scope{} = scope, %LexofficeReceipt{id: id}) do
    Repo.update_all(from(r in waiting_query(scope), where: r.id == ^id), set: [dismissed: true])
    :ok
  end

  @doc "The receipts proposed as fixed assets, the latest first."
  def asset_proposals(%Scope{} = scope) do
    keys = for c <- Category.all(), Category.fixed_asset?(c), do: c.key

    Repo.all(
      from r in owned(LexofficeReceipt, scope),
        where: is_nil(r.fixed_asset_id) and not r.asset_dismissed,
        where:
          fragment(
            "EXISTS (SELECT 1 FROM json_each(?) WHERE json_extract(value, '$.category') IN (SELECT value FROM json_each(?)))",
            r.items,
            ^JSON.encode!(keys)
          ),
        order_by: [desc: r.date, desc: r.id]
    )
    |> Enum.filter(&(purchase(&1) > 0))
  end

  @doc "The receipt's net purchase in Anlagevermögen categories, in cents."
  def purchase(%LexofficeReceipt{items: items}) do
    -Enum.sum(for item <- items, fixed_asset?(item), do: item.net)
  end

  defp fixed_asset?(%{category: key}) do
    case key && Category.get(key) do
      %Category{} = category -> Category.fixed_asset?(category)
      _none -> false
    end
  end

  @doc "The fixed asset the receipt proposes, for the owner to complete."
  def proposed_asset(%LexofficeReceipt{} = receipt) do
    %FixedAsset{
      name: receipt.contact || LexofficeReceipt.title(receipt),
      purchased_on: receipt.date,
      net: purchase(receipt)
    }
  end

  @doc """
  Records the fixed asset the receipt proposes with `attrs`; the proposal is done then. `{:error, :not_proposed}`
  when it is no longer proposed.
  """
  def create_asset(%Scope{} = scope, %LexofficeReceipt{id: id}, attrs) do
    proposed =
      from r in owned(LexofficeReceipt, scope),
        where: r.id == ^id and is_nil(r.fixed_asset_id) and not r.asset_dismissed

    Repo.transact(fn ->
      with {:ok, asset} <- FixedAssets.create(scope, attrs),
           {1, _rows} <- Repo.update_all(proposed, set: [fixed_asset_id: asset.id]) do
        {:ok, asset}
      else
        {0, _rows} -> {:error, :not_proposed}
        {:error, changeset} -> {:error, changeset}
      end
    end)
  end

  @doc "Dismisses the receipt's proposal of a fixed asset."
  def dismiss_asset(%Scope{} = scope, %LexofficeReceipt{id: id}) do
    Repo.update_all(from(r in owned(LexofficeReceipt, scope), where: r.id == ^id),
      set: [asset_dismissed: true]
    )

    :ok
  end

  @doc "The user's Lexoffice receipt with `id`, nil if there is none."
  def get(%Scope{} = scope, id) do
    case Abakus.Ids.cast(id) do
      {:ok, id} -> Repo.one(from r in owned(LexofficeReceipt, scope), where: r.id == ^id)
      :error -> nil
    end
  end
end
