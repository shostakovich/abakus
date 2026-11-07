defmodule Abakus.Bookkeeping do
  @moduledoc """
  Each user's Buchhaltung: which of their accounts are the business's, and the tax lines that give a transaction, or
  a part of a split, a bookkeeping category and VAT treatment, on any of their accounts. It annotates the Ledger's
  transactions and leads none; its tables are not synced. Transfers between the user's accounts take no tax line.

  The inbox lists the business accounts' transactions that still miss a category: in the register, not zero, no
  transfer and no opening balance, a split while one of its parts does.
  """

  import Ecto.Query
  import Abakus.Owned

  alias Abakus.Bookkeeping.{BusinessAccount, TaxLine}
  alias Abakus.{Ids, Ledger, Repo}
  alias Abakus.Ledger.{Account, Payee, Subtransaction, Transaction}
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

  @doc "The business transactions still missing a category, newest first, with payees and parts."
  def inbox(%Scope{} = scope) do
    from(t in Ledger.in_register(scope),
      where: t.account_id in subquery(business_accounts(scope)),
      where: is_nil(t.payee_id) or t.payee_id not in subquery(opening_payees(scope)),
      where:
        (t.id not in subquery(split_ids()) and t.amount != 0 and
           is_nil(t.transfer_transaction_id) and is_nil(t.transfer_subtransaction_id) and
           t.id not in subquery(whole_lines(scope))) or
          t.id in subquery(open_parts(scope)),
      order_by: [desc: t.date, desc: t.id],
      preload: [:payee, subtransactions: :payee]
    )
    |> Repo.all()
  end

  defp business_accounts(scope),
    do: from(b in owned(BusinessAccount, scope), select: b.account_id)

  defp opening_payees(scope),
    do:
      from(p in owned(Payee, scope),
        where: p.hidden and p.name == ^Ledger.opening_payee(),
        select: p.id
      )

  defp parts, do: from(s in Subtransaction, where: is_nil(s.deleted_at))

  defp split_ids, do: from(s in parts(), select: s.transaction_id)

  defp whole_lines(scope),
    do:
      from(l in owned(TaxLine, scope),
        where: is_nil(l.subtransaction_id),
        select: l.transaction_id
      )

  defp open_parts(scope) do
    part_lines =
      from l in owned(TaxLine, scope),
        where: not is_nil(l.subtransaction_id),
        select: l.subtransaction_id

    from s in parts(),
      where:
        s.amount != 0 and is_nil(s.transfer_transaction_id) and
          s.id not in subquery(part_lines),
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
    ids = Enum.map(transactions, & &1.id)
    counting = MapSet.new(for t <- transactions, side <- sides(t), do: {t.id, side})

    Repo.all(
      from l in owned(TaxLine, scope),
        where:
          fragment("? IN (SELECT value FROM json_each(?))", l.transaction_id, ^JSON.encode!(ids))
    )
    |> Map.new(&{{&1.transaction_id, &1.subtransaction_id}, &1})
    |> Map.filter(fn {key, _line} -> key in counting end)
  end

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
  :not_found}` when the transaction is no longer in the user's register.
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

    case for({side, %Ecto.Changeset{valid?: false} = c} <- changes, into: %{}, do: {side, c}) do
      invalid when invalid == %{} -> apply_changes(changes)
      invalid -> {:error, invalid}
    end
  end

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
