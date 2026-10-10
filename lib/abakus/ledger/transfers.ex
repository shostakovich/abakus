defmodule Abakus.Ledger.Transfers do
  @moduledoc """
  Keeps the counterparts of transfers for `Abakus.Ledger`; runs inside its database transactions.

  A side of a transfer is a transaction that is not a split, or a split's subtransaction, whose payee is a
  transfer payee. Its counterpart is a transaction in that payee's account with the negated amount, the same date
  and memo, and the side's account's transfer payee. Both point at each other. Cleared state, approval and flag
  belong to each side; the category follows the category rule.

  A reconciled counterpart is changed, moved or released only when `confirmed?` is true.
  """

  import Ecto.Query

  alias Abakus.Ledger.{Account, Matches, Payee, Subtransaction, Transaction, TransactionOrigin}
  alias Abakus.Repo
  alias Ecto.Changeset

  # What the Ledger keeps in step on a counterpart, in the order a refusal reports.
  @synced [:account_id, :payee_id, :amount, :date, :memo, :category_id]

  @doc """
  Releases the counterparts of subtransactions the changeset removes, before they are deleted. A released
  counterpart is soft-deleted and points nowhere. Fails with `{:reconciled, :account_id}` for a reconciled one.
  """
  def release_removed(%Changeset{valid?: false}, _confirmed?), do: :ok

  def release_removed(changeset, confirmed?) do
    changeset.changes
    |> Map.get(:subtransactions, [])
    |> Enum.filter(&(&1.action in [:replace, :delete]))
    |> Enum.map(& &1.data.transfer_transaction_id)
    |> release(confirmed?)
  end

  @doc """
  Creates, updates or releases the counterparts of a saved transaction and its subtransactions. `loaded` holds
  what the Ledger loaded to validate the write: the transaction's `account`, the `transfer_accounts` of its payees,
  its existing `counterparts` by id, and `confirmed?`.

  Fails with `:origin_taken` when a counterpart would move into an account that has one of its external ids, with
  `{:match_pending, field}` when the account or amount of a counterpart with an open match proposal would change,
  and with `{:reconciled, field}` when a reconciled counterpart would change without `confirmed?`.
  """
  def sync(%Transaction{transfer_subtransaction_id: id} = transaction, _loaded)
      when not is_nil(id),
      do: {:ok, transaction}

  def sync(%Transaction{} = transaction, loaded) do
    transaction = Repo.preload(transaction, :subtransactions)

    context = %{
      transaction: transaction,
      account: loaded.account,
      other_accounts: loaded.transfer_accounts,
      counterparts: loaded.counterparts,
      confirmed?: loaded.confirmed?,
      transfer_payee_id: transfer_payee_id(transaction.account_id, loaded.transfer_accounts)
    }

    with {:ok, transaction} <- sync_parent(transaction, context),
         {:ok, subtransactions} <- sync_subtransactions(transaction.subtransactions, context) do
      {:ok, %{transaction | subtransactions: subtransactions}}
    end
  end

  # Only needed when there is a transfer at all.
  defp transfer_payee_id(_account_id, transfer_accounts) when transfer_accounts == %{}, do: nil

  defp transfer_payee_id(account_id, _transfer_accounts),
    do: Repo.one!(from p in Payee, where: p.transfer_account_id == ^account_id, select: p.id)

  @doc "Transactions by id."
  def by_id(ids), do: Map.new(Repo.all(by_ids(ids)), &{&1.id, &1})

  @doc "The accounts of those payees that are transfer payees, by payee id."
  def accounts_by_payee(payee_ids) do
    Repo.all(
      from p in Payee,
        join: a in assoc(p, :transfer_account),
        where: p.id in ^Enum.reject(payee_ids, &is_nil/1),
        select: {p.id, a}
    )
    |> Map.new()
  end

  defp sync_parent(%Transaction{subtransactions: []} = transaction, context),
    do: sync_side(transaction, context)

  # A transaction that became a split is no transfer as a whole any more.
  defp sync_parent(transaction, context), do: unlink(transaction, context)

  defp sync_subtransactions(subtransactions, context) do
    subtransactions
    |> Enum.reduce_while({:ok, []}, fn subtransaction, {:ok, done} ->
      case sync_side(subtransaction, context) do
        {:ok, subtransaction} -> {:cont, {:ok, [subtransaction | done]}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, done} -> {:ok, Enum.reverse(done)}
      error -> error
    end
  end

  defp sync_side(side, context) do
    existing = Map.get(context.counterparts, side.transfer_transaction_id)

    case {counterpart_fields(side, existing, context), existing} do
      {nil, nil} -> {:ok, side}
      {nil, _existing} -> unlink(side, context)
      {fields, nil} -> create_counterpart(side, fields, context)
      {fields, existing} -> update_counterpart(side, existing, fields, context)
    end
  end

  defp counterpart_fields(side, existing, context) do
    with %Account{} = other <- Map.get(context.other_accounts, side.payee_id) do
      %{
        account_id: other.id,
        payee_id: context.transfer_payee_id,
        date: context.transaction.date,
        amount: -side.amount,
        memo: side.memo,
        category_id: counterpart_category(context.account, other, side, existing)
      }
    end
  end

  # Only the budget side of a transfer between a budget and a tracking account has a category.
  defp counterpart_category(account, other, side, existing) do
    if Account.takes_category?(other, account),
      do: side.counterpart_category_id || (existing && existing.category_id)
  end

  defp create_counterpart(side, fields, context) do
    %Transaction{
      cleared: :uncleared,
      approved: context.transaction.approved,
      source: context.transaction.source
    }
    |> Changeset.change(Map.merge(fields, back_pointer(side)))
    |> Repo.insert()
    |> case do
      {:ok, counterpart} ->
        side |> Changeset.change(transfer_transaction_id: counterpart.id) |> Repo.update()

      error ->
        error
    end
  end

  defp back_pointer(%Transaction{id: id}), do: %{transfer_transaction_id: id}
  defp back_pointer(%Subtransaction{id: id}), do: %{transfer_subtransaction_id: id}

  defp update_counterpart(side, existing, fields, context) do
    with :ok <- check_open_match(existing, fields),
         :ok <- check_reconciled(existing, fields, context.confirmed?),
         {:ok, counterpart} <- existing |> Changeset.change(fields) |> Repo.update(),
         :ok <- move_counterpart_origins(existing, counterpart) do
      {:ok, side}
    end
  end

  defp check_open_match(existing, fields) do
    field =
      cond do
        fields.account_id != existing.account_id -> :account_id
        fields.amount != existing.amount -> :amount
        true -> nil
      end

    if field && Matches.pending?(existing.id),
      do: {:error, {:match_pending, field}},
      else: :ok
  end

  defp check_reconciled(
         %Transaction{cleared: :reconciled} = existing,
         fields,
         false = _confirmed?
       ) do
    case Enum.find(@synced, &(Map.fetch!(fields, &1) != Map.fetch!(existing, &1))) do
      nil -> :ok
      field -> {:error, {:reconciled, field}}
    end
  end

  defp check_reconciled(_existing, _fields, _confirmed?), do: :ok

  defp move_counterpart_origins(%{account_id: account_id}, %{account_id: account_id}), do: :ok

  defp move_counterpart_origins(_before, counterpart),
    do: move_origins(counterpart.id, counterpart.id, counterpart.account_id)

  defp unlink(%{transfer_transaction_id: nil} = side, _context), do: {:ok, side}

  defp unlink(side, context) do
    with :ok <- release([side.transfer_transaction_id], context.confirmed?) do
      side |> Changeset.change(transfer_transaction_id: nil) |> Repo.update()
    end
  end

  defp release(ids, confirmed?) do
    ids = Enum.reject(ids, &is_nil/1)

    cond do
      ids == [] ->
        :ok

      not confirmed? and reconciled?(ids) ->
        {:error, {:reconciled, :account_id}}

      true ->
        soft_delete(ids)

        Repo.update_all(by_ids(ids),
          set: [
            transfer_transaction_id: nil,
            transfer_subtransaction_id: nil,
            updated_at: DateTime.utc_now()
          ]
        )

        :ok
    end
  end

  @doc "Whether any of the transactions is reconciled and not deleted."
  def reconciled?(ids) do
    Repo.exists?(from t in by_ids(ids), where: t.cleared == :reconciled and is_nil(t.deleted_at))
  end

  @doc """
  Soft-deletes transactions that are not deleted yet. Match proposals for them become ordinary imports again, and
  a deleted proposal stops proposing. Transfer pointers stay, so a deleted pair still shows what it was.
  """
  def soft_delete(ids) do
    now = DateTime.utc_now()

    Repo.update_all(from(t in by_ids(ids), where: is_nil(t.deleted_at)),
      set: [deleted_at: now, updated_at: now]
    )

    Repo.update_all(
      from(t in Transaction,
        where:
          not is_nil(t.matched_transaction_id) and
            (t.matched_transaction_id in ^ids or t.id in ^ids)
      ),
      set: [matched_transaction_id: nil, updated_at: now]
    )

    :ok
  end

  @doc """
  Moves the origins of transaction `from_id` to transaction `to_id` in `account_id`: along with a transaction that
  moves, or to the transaction a proposal is merged into. Returns `{:error, :origin_taken}` when that account has
  one of the external ids from the same source already.
  """
  def move_origins(from_id, to_id, account_id) do
    moving = from o in TransactionOrigin, where: o.transaction_id == ^from_id

    taken? =
      Repo.exists?(
        from o in moving,
          join: other in TransactionOrigin,
          on:
            other.source == o.source and other.external_id == o.external_id and
              other.account_id == ^account_id and other.id != o.id
      )

    if taken? do
      {:error, :origin_taken}
    else
      Repo.update_all(moving,
        set: [transaction_id: to_id, account_id: account_id, updated_at: DateTime.utc_now()]
      )

      :ok
    end
  end

  defp by_ids(ids), do: from(t in Transaction, where: t.id in ^Enum.reject(ids, &is_nil/1))
end
