defmodule Abakus.Ledger do
  @moduledoc """
  Accounts, payees and transactions.

  The Ledger owns transfers: a transaction or subtransaction with a transfer payee gets its counterpart in that
  payee's account, created, kept in step (amount negated, date, memo), moved, and removed by the Ledger alone
  (`Abakus.Ledger.Transfers`). For a transfer from a tracking to a budget account, `counterpart_category_id`
  gives the counterpart's category. Transfers to closed accounts are allowed (imported history has them); the UI
  does not offer closed accounts.

  Deleting either side of a transfer deletes both; deleting a split deletes the counterparts of its
  subtransactions. The counterpart of a subtransaction belongs to its split: it is changed and deleted there, so
  only its own fields (cleared, approved, flag, category) change on it directly.

  A reconciled transaction is locked: the Ledger refuses any change to it, made directly or through a transfer
  (a counterpart kept in step, moved, released or deleted), unless the caller passes `reconciled: :confirmed`
  after asking. Leaving the reconciled state is a change too.

  A match proposal (an import with `matched_transaction_id`) counts nowhere until `accept_match/1` merges it into
  the existing transaction or `reject_match/1` approves it as a transaction of its own. A transaction (or
  counterpart) cannot move into an account that has one of its external ids from the same source already.
  """

  import Ecto.Query

  alias Abakus.Categories.Category
  alias Abakus.Ledger.{Account, Matches, Payee, Transaction, TransactionOrigin, Transfers}
  alias Abakus.{Names, References, Repo}
  alias Ecto.Changeset

  def list_accounts, do: Repo.all(from a in Account, order_by: [a.position, a.id])

  def get_account!(id), do: Repo.get!(Account, id)

  @doc "Creates an account together with its transfer payee."
  def create_account(attrs) do
    Repo.transact(fn ->
      with {:ok, account} <- Repo.insert(Account.changeset(%Account{}, attrs)),
           {:ok, payee} <- Repo.insert(Payee.transfer_changeset(%Payee{}, account)) do
        {:ok, %{account | transfer_payee: payee}}
      end
    end)
  end

  @doc "Updates an account; renaming it renames its transfer payee. Returns it with its transfer payee."
  def update_account(%Account{} = account, attrs) do
    changeset = Account.changeset(account, attrs)

    Repo.transact(fn ->
      with {:ok, account} <- Repo.update(changeset),
           payee = Repo.get_by!(Payee, transfer_account_id: account.id),
           {:ok, payee} <-
             rename_transfer_payee(payee, account, Changeset.changed?(changeset, :name)) do
        {:ok, %{account | transfer_payee: payee}}
      end
    end)
  end

  defp rename_transfer_payee(payee, account, true = _renamed?),
    do: payee |> Payee.transfer_changeset(account) |> Repo.update()

  defp rename_transfer_payee(payee, _account, false = _renamed?), do: {:ok, payee}

  def create_payee(attrs) do
    %Payee{}
    |> Payee.changeset(attrs)
    |> References.validate_exists(:last_category_id, Category)
    |> Repo.insert()
  end

  def update_payee(%Payee{} = payee, attrs) do
    payee
    |> Payee.changeset(attrs)
    |> References.validate_exists(:last_category_id, Category)
    |> Repo.update()
  end

  @doc "Finds a payee by name, ignoring emoji and case. Regular payees win over transfer payees."
  def find_payee_by_name(name) when is_binary(name) do
    key = Names.lookup_key(name)

    Repo.all(from p in Payee, where: p.lookup_key == ^key)
    |> Enum.map(&{&1, is_nil(&1.transfer_account_id)})
    |> Names.pick()
  end

  @doc """
  The account's transactions, newest first, with their subtransactions; without deleted ones and match proposals,
  which count nowhere (see `list_match_proposals/1`).
  """
  def list_transactions(%Account{id: account_id}) do
    Repo.all(
      from t in in_register(),
        where: t.account_id == ^account_id,
        order_by: [desc: t.date, desc: t.id],
        preload: :subtransactions
    )
  end

  @doc "The account's pending match proposals with the transactions they would merge into."
  def list_match_proposals(%Account{id: account_id}) do
    Repo.all(
      from t in Transaction,
        where:
          t.account_id == ^account_id and is_nil(t.deleted_at) and
            not is_nil(t.matched_transaction_id),
        order_by: [desc: t.date, desc: t.id],
        preload: [:subtransactions, :matched_transaction]
    )
  end

  @doc "Transactions in the register, which count for listings and balances: not deleted and no match proposal."
  def in_register,
    do: from(t in Transaction, where: is_nil(t.deleted_at) and is_nil(t.matched_transaction_id))

  @doc """
  Creates a transaction, with subtransactions for a split. Checks the references and the rules for the accounts
  involved (`Transaction.validate_accounts/4`) and keeps the counterparts of transfers (`Abakus.Ledger.Transfers`).
  Approval defaults by source: manual entries are approved, imports and API entries are not. Categories are
  remembered as their payees' last categories.
  """
  def create_transaction(attrs) do
    Repo.transact(fn ->
      %Transaction{}
      |> Transaction.changeset(attrs)
      |> put_default_approval()
      |> write(&Repo.insert/1, [])
    end)
  end

  defp put_default_approval(changeset) do
    manual? = Changeset.get_field(changeset, :source) == :manual

    if Map.has_key?(changeset.params, "approved"),
      do: changeset,
      else: Changeset.put_change(changeset, :approved, manual?)
  end

  @doc """
  Updates a transaction as stored (the struct only names it) and its counterparts. A deleted transaction cannot
  be changed; the counterpart of a split's subtransaction changes only its own fields (cleared, approved, flag,
  category), the rest in its split. When the account changes, the origins move along. A change that alters a
  reconciled transaction or counterpart needs `reconciled: :confirmed`.
  """
  def update_transaction(%Transaction{id: id}, attrs, opts \\ []) do
    Repo.transact(fn ->
      Transaction
      |> Repo.get!(id)
      |> Repo.preload(:subtransactions)
      |> Transaction.changeset(attrs)
      |> write(&Repo.update/1, opts)
    end)
  end

  # Validates and saves inside the caller's database transaction; the accounts and counterparts involved are
  # loaded once for both.
  defp write(changeset, save, opts) do
    context = context(changeset, opts)

    changeset
    |> validate_references()
    |> Matches.validate()
    |> validate_accounts(context)
    |> validate_reconciled(context.confirmed?)
    |> save(save, context)
  end

  defp context(changeset, opts) do
    sides = [changeset | Transaction.subtransactions(changeset)]
    account_id = Changeset.get_field(changeset, :account_id)
    counterpart_ids = Enum.map(sides, &Changeset.get_field(&1, :transfer_transaction_id))

    %{
      account: account_id && Repo.get(Account, account_id),
      transfer_accounts:
        Transfers.accounts_by_payee(Enum.map(sides, &Changeset.get_field(&1, :payee_id))),
      counterparts: Transfers.by_id(counterpart_ids),
      confirmed?: Keyword.get(opts, :reconciled) == :confirmed
    }
  end

  defp validate_references(changeset) do
    sides = [changeset | Transaction.subtransactions(changeset)]
    payees = References.existing(Payee, changed_ids(sides, :payee_id))

    categories =
      References.existing(
        Category,
        changed_ids(sides, :category_id) ++ changed_ids(sides, :counterpart_category_id)
      )

    check = fn changeset ->
      changeset
      |> References.validate(:payee_id, payees)
      |> References.validate(:category_id, categories)
      |> References.validate(:counterpart_category_id, categories)
    end

    changeset
    |> check.()
    |> Transaction.update_subtransactions(check)
  end

  defp changed_ids(changesets, field), do: Enum.map(changesets, &Changeset.get_change(&1, field))

  defp validate_accounts(changeset, context) do
    case {Changeset.get_field(changeset, :account_id), context.account} do
      {nil, _account} ->
        changeset

      {_id, nil} ->
        References.not_found(changeset, :account_id)

      {_id, account} ->
        categories = Map.new(context.counterparts, fn {id, t} -> {id, t.category_id} end)

        changeset
        |> Transaction.validate_accounts(account, context.transfer_accounts, categories)
        |> Matches.validate_proposal(context.transfer_accounts)
    end
  end

  @reconciled "ist abgeschlossen"
  @counterpart_reconciled "betrifft eine abgeschlossene Gegenbuchung"

  # The counterpart's category is checked where it would change.
  defp validate_reconciled(
         %Changeset{data: %Transaction{cleared: :reconciled}} = changeset,
         false
       ) do
    if Map.delete(changeset.changes, :counterpart_category_id) == %{},
      do: changeset,
      else: Changeset.add_error(changeset, :cleared, @reconciled)
  end

  defp validate_reconciled(changeset, _confirmed?), do: changeset

  @origin_taken "enthält diese Buchung schon aus derselben Quelle"
  @counterpart_origin_taken "führt in ein Konto, das diese Buchung schon aus derselben Quelle enthält"
  @counterpart_locked "kann nicht geändert werden, solange die Gegenbuchung einen offenen Zuordnungsvorschlag hat"

  defp save(changeset, save, context) do
    with :ok <- release_removed(changeset, context),
         {:ok, transaction} <- save.(changeset),
         :ok <- move_origins(changeset, transaction),
         {:ok, transaction} <- sync(changeset, transaction, context) do
      remember_categories(transaction)
      {:ok, transaction}
    end
  end

  defp release_removed(changeset, context) do
    case Transfers.release_removed(changeset, context.confirmed?) do
      :ok ->
        :ok

      {:error, {:reconciled, _field}} ->
        {:error, failed(changeset, :subtransactions, @counterpart_reconciled)}
    end
  end

  defp move_origins(%Changeset{data: %Transaction{id: id}} = changeset, transaction)
       when not is_nil(id) do
    if Changeset.changed?(changeset, :account_id),
      do: move_origins(changeset, id, transaction.account_id),
      else: :ok
  end

  defp move_origins(_new, _transaction), do: :ok

  defp move_origins(changeset, id, account_id) do
    case Transfers.move_origins(id, id, account_id) do
      :ok -> :ok
      {:error, :origin_taken} -> {:error, failed(changeset, :account_id, @origin_taken)}
    end
  end

  defp sync(changeset, transaction, context) do
    case Transfers.sync(transaction, context) do
      {:error, :origin_taken} ->
        {:error, sync_failed(changeset, transaction, :account_id, @counterpart_origin_taken)}

      {:error, {:match_pending, field}} ->
        {:error, sync_failed(changeset, transaction, field, @counterpart_locked)}

      {:error, {:reconciled, field}} ->
        {:error, sync_failed(changeset, transaction, field, @counterpart_reconciled)}

      synced ->
        synced
    end
  end

  # The side's field a counterpart's field follows: its account the payee, its payee the account, its category
  # `counterpart_category_id`, the rest the same field. A split's follow its subtransactions, but for the date.
  @follows %{account_id: :payee_id, payee_id: :account_id, category_id: :counterpart_category_id}

  defp sync_failed(changeset, transaction, counterpart_field, message) do
    field =
      cond do
        counterpart_field == :date -> :date
        transaction.subtransactions != [] -> :subtransactions
        true -> Map.get(@follows, counterpart_field, counterpart_field)
      end

    failed(changeset, field, message)
  end

  defp failed(changeset, field, message),
    do: %{Changeset.add_error(changeset, field, message) | action: :update}

  # A match proposal is no booking yet, so it leaves the payee alone.
  defp remember_categories(%Transaction{matched_transaction_id: id}) when not is_nil(id), do: :ok

  defp remember_categories(transaction) do
    for %{payee_id: payee_id, category_id: category_id} <- [
          transaction | transaction.subtransactions
        ],
        payee_id && category_id do
      Repo.update_all(
        from(p in Payee, where: p.id == ^payee_id and is_nil(p.transfer_account_id)),
        set: [last_category_id: category_id, updated_at: DateTime.utc_now()]
      )
    end
  end

  @doc """
  Soft-deletes a transaction with every transfer counterpart: deleting either side of a transfer deletes both,
  deleting a split deletes the counterparts of its subtransactions. The counterpart of a subtransaction is
  deleted with its split, so deleting it on its own is refused. Deleting a deleted transaction changes nothing.
  Deleting a reconciled transaction, or one with a reconciled counterpart, needs `reconciled: :confirmed`.
  """
  def delete_transaction(%Transaction{id: id}, opts \\ []) do
    confirmed? = Keyword.get(opts, :reconciled) == :confirmed

    Repo.transact(fn ->
      transaction = Transaction |> Repo.get!(id) |> Repo.preload(:subtransactions)
      ids = pair_ids(transaction)

      cond do
        transaction.deleted_at ->
          {:ok, transaction}

        transaction.transfer_subtransaction_id ->
          delete_failed(
            transaction,
            :transfer_subtransaction_id,
            "wird mit ihrer Aufteilung gelöscht"
          )

        not confirmed? and transaction.cleared == :reconciled ->
          delete_failed(transaction, :cleared, @reconciled)

        not confirmed? and Transfers.reconciled?(ids) ->
          delete_failed(transaction, pair_field(transaction), @counterpart_reconciled)

        true ->
          Transfers.soft_delete(ids)
          {:ok, Transaction |> Repo.get!(id) |> Repo.preload(:subtransactions)}
      end
    end)
  end

  defp pair_field(%Transaction{subtransactions: []}), do: :transfer_transaction_id
  defp pair_field(_split), do: :subtransactions

  defp delete_failed(transaction, field, message) do
    {:error,
     transaction
     |> Changeset.change()
     |> Changeset.add_error(field, message)
     |> Map.put(:action, :delete)}
  end

  # Pointers are symmetric (the Ledger alone sets them), so these are all sides involved.
  defp pair_ids(transaction) do
    ids = Enum.map([transaction | transaction.subtransactions], & &1.transfer_transaction_id)
    Enum.reject([transaction.id | ids], &is_nil/1)
  end

  @doc """
  Accepts a match proposal: the existing transaction survives with its id, payee and amount, keeps its category
  and memo where it has them (else takes the import's), takes the import's date (unless a split owns it) and
  cleared state, is approved and gets the import's origins; the proposal is removed. The rules for a new proposal
  are checked again, so a transaction reconciled meanwhile refuses it. `opts` go to `update_transaction/3`.
  """
  def accept_match(%Transaction{id: id}, opts \\ []) do
    Repo.transact(fn ->
      with {:ok, proposal} <- pending_proposal(id),
           existing = Repo.get(Transaction, proposal.matched_transaction_id),
           :ok <- check_match(proposal, existing),
           :ok <- take_origins(proposal, existing) do
        Repo.delete!(proposal)

        update_transaction(
          existing,
          Matches.merged(Repo.preload(existing, :subtransactions), proposal),
          opts
        )
      end
    end)
  end

  defp check_match(proposal, existing) do
    changeset = proposal |> Changeset.change() |> Matches.validate_target(existing)
    if changeset.valid?, do: :ok, else: {:error, %{changeset | action: :update}}
  end

  defp take_origins(proposal, existing) do
    with {:error, :origin_taken} <-
           Transfers.move_origins(proposal.id, existing.id, existing.account_id) do
      {:error, failed(Changeset.change(proposal), :account_id, @origin_taken)}
    end
  end

  @doc "Rejects a match proposal (\"Trennen\"): the import stays as a transaction of its own and is approved."
  def reject_match(%Transaction{id: id}) do
    Repo.transact(fn ->
      with {:ok, proposal} <- pending_proposal(id) do
        proposal |> Changeset.change(matched_transaction_id: nil, approved: true) |> Repo.update()
      end
    end)
  end

  defp pending_proposal(id) do
    case Repo.get!(Transaction, id) do
      %Transaction{deleted_at: nil, matched_transaction_id: matched} = proposal
      when not is_nil(matched) ->
        {:ok, proposal}

      _transaction ->
        {:error, :not_a_proposal}
    end
  end

  @doc "Records where a transaction was imported from; the account is the one the transaction is in now."
  def add_origin(%Transaction{id: id}, source, external_id) do
    case Repo.one(from t in Transaction, where: t.id == ^id, select: t.account_id) do
      nil ->
        changeset = Changeset.change(%TransactionOrigin{transaction_id: id})
        {:error, %{References.not_found(changeset, :transaction_id) | action: :insert}}

      account_id ->
        %TransactionOrigin{transaction_id: id, account_id: account_id}
        |> TransactionOrigin.changeset(%{source: source, external_id: external_id})
        |> Repo.insert()
    end
  end

  @doc "The transaction an external id was imported as or matched to, deleted ones and proposals included."
  def get_transaction_by_origin(%Account{id: account_id}, source, external_id) do
    Repo.one(
      from t in Transaction,
        join: o in assoc(t, :origins),
        where:
          o.account_id == ^account_id and o.source == ^source and o.external_id == ^external_id
    )
  end
end
