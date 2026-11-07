defmodule Abakus.Bookkeeping do
  @moduledoc """
  Each user's Buchhaltung: which of their accounts are the business's, and the tax lines that give a transaction, or
  a part of a split, a bookkeeping category and VAT treatment, on any of their accounts. It annotates the Ledger's
  transactions and leads none; its tables are not synced. Transfers between the user's accounts take no tax line.

  The inbox lists the business accounts' transactions that still miss a category or an attachment
  (`Abakus.Bookkeeping.Attachments`): in the register, not zero, no transfer and no opening balance, a split while one
  of its parts does; one on another account while a side with a tax line misses an attachment. An attachment of the
  whole split counts for all its parts, and a transaction marked so needs none, as does an invoice's payment
  (`Abakus.Bookkeeping.InvoicePayments`), whose proof is the invoice. A transaction that pays a disposal
  (`Abakus.Bookkeeping.FixedAssets`) needs no category. A transaction in a period locked by a sent return
  (`Abakus.Bookkeeping.Filings`) is out of the inbox, and its tax lines can no longer change.
  """

  import Ecto.Query
  import Abakus.Owned
  import Abakus.JsonList

  alias Abakus.Bookkeeping.{
    Attachment,
    BusinessAccount,
    Category,
    Disposal,
    Filings,
    InvoicePayment,
    LexofficeReceipt,
    ReceiptWaiver,
    TaxLine
  }

  alias Abakus.{Ids, Ledger, Repo}
  alias Abakus.Ledger.{Account, Subtransaction, Transaction}
  alias Abakus.Users.{Scope, User}

  @doc "Whether the user keeps books: they have a business account."
  def in_use?(%User{id: id}),
    do: Repo.exists?(from b in BusinessAccount, where: b.user_id == ^id)

  @doc "The ids of the user's business accounts."
  def business_account_ids(%Scope{} = scope),
    do: Repo.all(from b in owned(BusinessAccount, scope), select: b.account_id)

  @doc "Makes the user's accounts `ids` their business accounts, and only those; ids of other accounts are ignored."
  def put_business_accounts(%Scope{} = scope, ids) do
    ids = for id <- ids, {:ok, id} <- [Ids.cast(id)], do: id
    ids = Repo.all(from a in owned(Account, scope), where: a.id in ^ids, select: a.id)
    user_id = user_id(scope)
    now = DateTime.utc_now()

    Repo.transact(fn ->
      Repo.delete_all(from b in owned(BusinessAccount, scope), where: b.account_id not in ^ids)

      Repo.insert_all(
        BusinessAccount,
        Enum.map(ids, &%{account_id: &1, user_id: user_id, inserted_at: now, updated_at: now}),
        on_conflict: :nothing,
        conflict_target: :account_id
      )

      {:ok, ids}
    end)
  end

  @doc """
  The business transactions still missing a category or an attachment, newest first, with payees and parts, each as
  `{transaction, missing}` with `:category`, `:attachment` or both.
  """
  def inbox(%Scope{} = scope) do
    without_category = MapSet.new(Repo.all(without_category(scope)))
    without_attachment = MapSet.new(Repo.all(without_attachment(scope)))
    ids = without_category |> MapSet.union(without_attachment) |> MapSet.to_list()

    from(t in Transaction,
      where: in_json(t.id, ids),
      order_by: [desc: t.date, desc: t.id],
      preload: [:payee, subtransactions: :payee]
    )
    |> Repo.all()
    |> Enum.map(fn t ->
      {t,
       for(
         {kind, open} <- [category: without_category, attachment: without_attachment],
         t.id in open,
         do: kind
       )}
    end)
  end

  defp without_category(scope) do
    from t in open(scope, whole_lines(scope), part_lines(scope)),
      where: t.id not in subquery(disposal_payments(scope))
  end

  defp without_attachment(scope) do
    whole = whole_attachments(scope)
    parts = part_attachments(scope)

    open(scope, whole, parts)
    |> missing_attachment(scope, whole)
    |> union(^missing_attachment(taxed_elsewhere(scope, whole, parts), scope, whole))
  end

  defp missing_attachment(query, scope, whole) do
    from t in query,
      where: t.id not in subquery(whole),
      where:
        t.id not in subquery(from w in owned(ReceiptWaiver, scope), select: w.transaction_id),
      where:
        t.id not in subquery(from p in owned(InvoicePayment, scope), select: p.transaction_id)
  end

  # On another account only the sides with a tax line are business, and so need an attachment.
  defp taxed_elsewhere(scope, whole_done, parts_done) do
    from(t in Ledger.in_register(scope),
      where: t.account_id not in subquery(business_accounts(scope)),
      where:
        (t.id not in subquery(split_ids()) and t.amount != 0 and
           t.id in subquery(whole_lines(scope)) and t.id not in subquery(whole_done)) or
          t.id in subquery(open_taxed_parts(scope, parts_done)),
      select: t.id
    )
    |> Ledger.without_opening_balances(scope)
    |> where(^dynamic(not (^Filings.locked_date(scope))))
  end

  # A transaction that is no split counts while its whole is not `done`, a split while one of its parts is not.
  defp open(scope, whole_done, parts_done) do
    from(t in business_transactions(scope),
      where:
        (t.id not in subquery(split_ids()) and t.amount != 0 and
           is_nil(t.transfer_transaction_id) and is_nil(t.transfer_subtransaction_id) and
           t.id not in subquery(whole_done)) or
          t.id in subquery(open_parts(parts_done)),
      select: t.id
    )
    |> where(^dynamic(not (^Filings.locked_date(scope))))
  end

  @doc "The business accounts' transactions in the register, without their opening balance."
  def business_transactions(%Scope{} = scope) do
    from(t in Ledger.in_register(scope),
      where: t.account_id in subquery(business_accounts(scope))
    )
    |> Ledger.without_opening_balances(scope)
  end

  @doc """
  The ids of the transactions that already pay something, so that they pay nothing else: an invoice, a disposal
  other than the one with the id `except_disposal`, or a Lexoffice receipt.
  """
  def claimed_transactions(%Scope{} = scope, except_disposal \\ nil) do
    disposals =
      from d in owned(Disposal, scope),
        where: not is_nil(d.transaction_id),
        select: d.transaction_id

    disposals =
      if except_disposal, do: where(disposals, [d], d.id != ^except_disposal), else: disposals

    receipts =
      from r in owned(LexofficeReceipt, scope),
        where: not is_nil(r.transaction_id),
        select: r.transaction_id

    from(p in owned(InvoicePayment, scope), select: p.transaction_id)
    |> union_all(^disposals)
    |> union_all(^receipts)
  end

  defp business_accounts(scope),
    do: from(b in owned(BusinessAccount, scope), select: b.account_id)

  defp parts, do: from(s in Subtransaction, where: is_nil(s.deleted_at))

  defp split_ids, do: from(s in parts(), select: s.transaction_id)

  defp whole_lines(scope),
    do:
      from(l in owned(TaxLine, scope),
        where: is_nil(l.subtransaction_id),
        select: l.transaction_id
      )

  defp part_lines(scope),
    do:
      from(l in owned(TaxLine, scope),
        where: not is_nil(l.subtransaction_id),
        select: l.subtransaction_id
      )

  defp whole_attachments(scope),
    do:
      from(a in owned(Attachment, scope),
        where: is_nil(a.subtransaction_id),
        select: a.transaction_id
      )

  defp part_attachments(scope),
    do:
      from(a in owned(Attachment, scope),
        where: not is_nil(a.subtransaction_id),
        select: a.subtransaction_id
      )

  defp open_taxed_parts(scope, done) do
    from s in parts(),
      where: s.amount != 0 and s.id in subquery(part_lines(scope)) and s.id not in subquery(done),
      select: s.transaction_id
  end

  defp open_parts(done) do
    from s in parts(),
      where: s.amount != 0 and is_nil(s.transfer_transaction_id) and s.id not in subquery(done),
      select: s.transaction_id
  end

  @doc """
  The sides of a transaction that take a tax line: `nil` for the whole transaction, else the parts of its split, by
  their ids; none for a transfer. Needs the subtransactions.
  """
  def sides(%Transaction{transfer_transaction_id: nil, transfer_subtransaction_id: nil} = t) do
    case t.subtransactions do
      [] -> [nil]
      parts -> for part <- parts, is_nil(part.transfer_transaction_id), do: part.id
    end
  end

  def sides(%Transaction{}), do: []

  @doc """
  The tax lines of `transactions` that count, by `{transaction_id, side}` as `sides/1` names the sides. Needs their
  subtransactions.
  """
  def tax_lines(%Scope{} = scope, transactions) do
    counting = MapSet.new(for t <- transactions, side <- sides(t), do: {t.id, side})

    Repo.all(
      from l in owned(TaxLine, scope),
        where: in_json(l.transaction_id, ids(transactions))
    )
    |> Map.new(&{{&1.transaction_id, &1.subtransaction_id}, &1})
    |> Map.filter(fn {key, _line} -> key in counting end)
  end

  @doc """
  The tax lines that count from `first` to `last`, as `Abakus.Bookkeeping.VatReturn` takes them, on any of the user's
  accounts. The owner is taxed on receipts (Ist-Versteuerung), so a tax line counts on its transaction's date; a
  part of a split counts with its own amount. A transaction that pays a disposal counts through the disposal.
  """
  def entries(%Scope{} = scope, %Date{} = first, %Date{} = last) do
    transactions =
      Repo.all(
        from t in Ledger.in_register(scope),
          where: t.date >= ^first and t.date <= ^last,
          where: t.id in subquery(from l in owned(TaxLine, scope), select: l.transaction_id),
          where: t.id not in subquery(disposal_payments(scope)),
          preload: :subtransactions
      )

    by_id = Map.new(transactions, &{&1.id, &1})

    for {{id, side}, line} <- tax_lines(scope, transactions),
        category = Category.get(line.category),
        category != nil do
      transaction = by_id[id]

      %{
        date: transaction.date,
        category: category,
        vat: line.vat,
        amount: amount(transaction, side)
      }
    end
  end

  defp amount(transaction, nil), do: transaction.amount

  defp amount(transaction, part_id),
    do: Enum.find_value(transaction.subtransactions, &(&1.id == part_id && &1.amount))

  defp disposal_payments(scope),
    do:
      from(d in owned(Disposal, scope),
        where: not is_nil(d.transaction_id),
        select: d.transaction_id
      )

  @doc "The disposal the transaction pays, with its asset; nil if it pays none."
  def paid_disposal(%Scope{} = scope, %Transaction{id: id}),
    do:
      Repo.one(
        from d in owned(Disposal, scope), where: d.transaction_id == ^id, preload: :fixed_asset
      )

  @doc "The user's transaction with what `sides/1` needs, nil if there is none in the register."
  def get_transaction(%Scope{} = scope, id) do
    case Ledger.get_transaction(scope, id) do
      %Transaction{deleted_at: nil, matched_transaction_id: nil} = transaction -> transaction
      _none -> nil
    end
  end

  @doc """
  Sets the tax lines of a transaction's sides from `params`, keyed by side (`"transaction"` for the whole, else the
  part's id) with `"category"` and `"vat"`; a side without category loses its line, and sides not in `params` keep
  theirs. `{:error, changesets}` maps each invalid side to its changeset, and nothing is saved; `{:error,
  :not_found}` when the transaction is no longer in the user's register, `{:error, :locked}` when it would change a
  tax line of a locked period, `{:error, :pays_disposal}` when it would set one on a disposal's payment.
  """
  def save_tax_lines(%Scope{} = scope, %Transaction{id: id}, params) do
    case get_transaction(scope, id) do
      nil -> {:error, :not_found}
      transaction -> save_sides(scope, transaction, params)
    end
  end

  defp save_sides(scope, transaction, params) do
    lines = tax_lines(scope, [transaction])

    changes =
      for side <- sides(transaction), attrs = params[side_key(side)], attrs != nil do
        change(scope, transaction, side, lines[{transaction.id, side}], attrs)
      end

    invalid = for {side, %Ecto.Changeset{valid?: false} = c} <- changes, into: %{}, do: {side, c}

    cond do
      Enum.any?(changes, &changes?/1) and Filings.locked?(scope, transaction.date) ->
        {:error, :locked}

      Enum.any?(changes, &sets_line?/1) and paid_disposal(scope, transaction) != nil ->
        {:error, :pays_disposal}

      invalid != %{} ->
        {:error, invalid}

      true ->
        apply_changes(changes)
    end
  end

  defp sets_line?({_side, %Ecto.Changeset{}} = change), do: changes?(change)
  defp sets_line?(_change), do: false

  defp changes?({_side, nil}), do: false
  defp changes?({_side, {:delete, _line}}), do: true
  defp changes?({_side, %Ecto.Changeset{changes: changes}}), do: changes != %{}

  defp change(scope, transaction, side, line, attrs) do
    if blank?(attrs["category"]) do
      {side_key(side), line && {:delete, line}}
    else
      line =
        line ||
          %TaxLine{
            user_id: user_id(scope),
            transaction_id: transaction.id,
            subtransaction_id: side
          }

      {side_key(side), TaxLine.changeset(line, attrs)}
    end
  end

  defp apply_changes(changes) do
    Repo.transact(fn ->
      Enum.reduce_while(changes, {:ok, []}, fn
        {_side, nil}, acc -> {:cont, acc}
        {_side, {:delete, line}}, acc -> {:cont, delete_line(line, acc)}
        {side, changeset}, {:ok, saved} -> save_line(side, changeset, saved)
      end)
    end)
  end

  defp delete_line(line, {:ok, saved}) do
    Repo.delete!(line, allow_stale: true)
    {:ok, saved}
  end

  defp save_line(side, changeset, saved) do
    case Repo.insert_or_update(changeset) do
      {:ok, line} -> {:cont, {:ok, [line | saved]}}
      {:error, changeset} -> {:halt, {:error, %{side => changeset}}}
    end
  end

  @doc "The key of a side in the params of `save_tax_lines/3`."
  def side_key(nil), do: "transaction"
  def side_key(subtransaction_id), do: subtransaction_id

  defp blank?(value), do: value in [nil, ""]
end
