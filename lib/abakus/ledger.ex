defmodule Abakus.Ledger do
  @moduledoc """
  Accounts, payees and transactions, each the user's: functions take the caller's `%Scope{}` and see only its
  user's records and categories; another user's behave like missing ones. Every write goes through `Abakus.Sync`,
  which records it as messages, and deletes as tombstones.

  The Ledger owns transfers: a transaction or subtransaction with a transfer payee gets its counterpart in that
  payee's account, created, kept in step (amount negated, date, memo), moved, and removed by the Ledger alone
  (`Abakus.Ledger.Transfers`). For a transfer from a tracking to a budget account, `counterpart_category_id`
  gives the counterpart's category. Transfers to closed accounts are allowed (imported history has them); the UI
  does not offer closed accounts.

  Deleting either side of a transfer deletes both; deleting a split deletes the counterparts of its
  subtransactions. The counterpart of a subtransaction belongs to its split: it is changed and deleted there, so
  only its own fields (cleared, approved, category) change on it directly.

  A reconciled transaction is locked: the Ledger refuses any change to it, made directly, through a transfer
  (a counterpart kept in step, moved, released or deleted) or by moving its category (`recategorize/4`), unless the
  caller passes `reconciled: :confirmed` after asking. Leaving the reconciled state is a change too.

  A transaction written by another area refers to its source (`led_by/2`), which leads amount, date, account, payee
  and transfer counterpart (`led_fields/0`): the Ledger refuses changes to them, and deleting it, unless the caller
  passes `led_by:` with that source. Both sides of a transfer are led by the source of either. Category, memo,
  cleared state and approval stay anyone's.

  A match proposal (an import with `matched_transaction_id`, see `find_matches/4`) counts nowhere until
  `accept_match/3` merges it into the existing transaction or `reject_match/2` approves it as a transaction of its
  own; a change of its transaction's account or amount by the transaction's source or through the transfer's other
  side dissolves it. A transaction (or counterpart) cannot move into an account that has one of its external ids from
  the same source already.
  """

  import Ecto.Query
  import Abakus.Owned

  alias Abakus.Categories
  alias Abakus.Categories.Category

  alias Abakus.Ledger.{
    Account,
    BankBalance,
    Matches,
    Payee,
    PayeeRenameCondition,
    ScheduledSubtransaction,
    ScheduledTransaction,
    Subtransaction,
    Transaction,
    TransactionOrigin,
    Transfers
  }

  alias Abakus.{Ids, Names, References, Repo, Successors, Sync}
  alias Abakus.Users.Scope
  alias Ecto.Changeset

  defmacrop month(date) do
    quote do: type(fragment("strftime('%Y-%m-01', ?)", unquote(date)), :date)
  end

  # Whether an external id is a pending import's, in SQL; instr, unlike LIKE, minds the case.
  defmacrop pending?(external_id) do
    quote do
      fragment("instr(?, ?) = 1", unquote(external_id), ^TransactionOrigin.pending_prefix())
    end
  end

  @doc "The accounts in their order, with their transfer payees."
  def list_accounts(%Scope{} = scope),
    do:
      Repo.all(
        from a in owned(Account, scope), order_by: [a.position, a.id], preload: :transfer_payee
      )

  def get_account!(%Scope{} = scope, id), do: Repo.get!(owned(Account, scope), id)

  @doc "Like `get_account!/2`, but nil for an id that is no account."
  def get_account(%Scope{} = scope, id) do
    case Ids.cast(id) do
      {:ok, id} -> Repo.get(owned(Account, scope), id)
      :error -> nil
    end
  end

  def change_account(%Account{} = account, attrs \\ %{}), do: Account.changeset(account, attrs)

  @doc "Creates an account together with its transfer payee; without a position it goes after the others."
  def create_account(%Scope{} = scope, attrs) do
    Sync.write(fn ->
      changeset =
        %Account{user_id: user_id(scope)} |> Account.changeset(attrs) |> put_next_position(scope)

      with {:ok, account} <- Sync.insert(changeset),
           {:ok, payee} <-
             Sync.insert(Payee.transfer_changeset(%Payee{user_id: account.user_id}, account)) do
        {:ok, %{account | transfer_payee: payee}}
      end
    end)
  end

  @doc "Creates the transfer payee of each of the accounts `ids` that lacks one, as part of a write."
  def put_missing_transfer_payees(%Scope{} = scope, ids) do
    Repo.all(
      from a in owned(Account, scope),
        left_join: p in Payee,
        on: p.transfer_account_id == a.id,
        where: a.id in ^ids and is_nil(p.id)
    )
    |> Enum.each(&Sync.insert!(Payee.transfer_changeset(%Payee{user_id: &1.user_id}, &1)))
  end

  # Cast params have string keys; a given 0 counts as given, though it changes nothing.
  defp put_next_position(changeset, scope) do
    if Map.has_key?(changeset.params, "position"),
      do: changeset,
      else: Changeset.put_change(changeset, :position, next_account_position(scope))
  end

  defp next_account_position(scope),
    do: Repo.one(from a in owned(Account, scope), select: coalesce(max(a.position) + 1, 0))

  @doc "Updates an account; renaming it renames its transfer payee. Returns it with its transfer payee."
  def update_account(%Scope{} = scope, %Account{} = account, attrs) do
    changeset = scope |> own!(account) |> Account.changeset(attrs)

    Sync.write(fn ->
      with {:ok, account} <- Sync.update(changeset),
           payee = Repo.get_by!(Payee, transfer_account_id: account.id),
           {:ok, payee} <-
             rename_transfer_payee(payee, account, Changeset.changed?(changeset, :name)) do
        {:ok, %{account | transfer_payee: payee}}
      end
    end)
  end

  defp rename_transfer_payee(payee, account, true = _renamed?),
    do: payee |> Payee.transfer_changeset(account) |> Sync.update()

  defp rename_transfer_payee(payee, _account, false = _renamed?), do: {:ok, payee}

  @doc "The account a file's account (`BANKID`, nil for a card, and `ACCTID`) is linked to, if any."
  def get_account_by_ofx(%Scope{} = scope, bank_id, acct_id) when is_binary(acct_id) do
    query = from a in owned(Account, scope), where: a.ofx_acct_id == ^acct_id

    query =
      if bank_id,
        do: where(query, [a], a.ofx_bank_id == ^bank_id),
        else: where(query, [a], is_nil(a.ofx_bank_id))

    Repo.one(query)
  end

  @doc """
  Links the account to a file's account, so later files find it; an account has one link, and an account that had
  this one loses it.
  """
  def link_ofx_account(%Scope{} = scope, %Account{} = account, bank_id, acct_id) do
    own!(scope, account)

    Sync.write(fn ->
      with %Account{id: id} = linked when id != account.id <-
             get_account_by_ofx(scope, bank_id, acct_id) do
        Sync.update!(Account.ofx_changeset(linked, nil, nil))
      end

      account |> Account.ofx_changeset(bank_id, acct_id) |> Sync.update()
    end)
  end

  @doc "Records what the bank reports the account holds on a date; another one for that source and date replaces it."
  def put_bank_balance(%Scope{} = scope, %Account{} = account, attrs) do
    %Account{id: account_id, user_id: user_id} = own!(scope, account)

    %BankBalance{account_id: account_id, user_id: user_id}
    |> BankBalance.changeset(attrs)
    |> Repo.insert(
      on_conflict: {:replace, [:amount, :updated_at]},
      conflict_target: [:account_id, :source, :date],
      returning: true
    )
  end

  @doc "The account's newest bank balance from any source, the one reconciling offers; nil without one."
  def latest_bank_balance(%Scope{} = scope, %Account{id: account_id}) do
    Repo.one(
      from b in owned(BankBalance, scope),
        where: b.account_id == ^account_id,
        order_by: [desc: b.date, desc: b.updated_at, desc: b.id],
        limit: 1
    )
  end

  @doc "What the account's cleared and reconciled register transactions dated up to `through` add up to."
  def cleared_balance(%Scope{} = scope, %Account{id: account_id}, %Date{} = through) do
    Repo.one(
      from t in cleared_through(scope, account_id, through),
        select: coalesce(sum(t.amount), 0)
    )
  end

  defp cleared_through(scope, account_id, through),
    do:
      from(t in in_register(scope),
        where: t.account_id == ^account_id and t.cleared != :uncleared and t.date <= ^through
      )

  @adjustment_payee "Ausgleichsbuchung"
  @adjustment_memo "Beim Abgleichen automatisch angelegt"

  @doc """
  Reconciles the account against the bank's balance `%{amount, date, through}`: its cleared balance up to
  `through` must differ from `amount` by `adjust` (default 0, the difference the user saw), else the difference is
  refused as `{:error, {:difference, cents}}`. A difference is booked first as an adjustment dated `date`: payee
  "Ausgleichsbuchung", approved, in a budget account to Ready to Assign. Then the approved cleared transactions in
  the register dated up to `through` become reconciled, but not the ones an open match proposal waits for, and the
  account's last reconciled at is now. Returns how many transactions were reconciled and the adjustment, if any.
  """
  def reconcile(
        %Scope{} = scope,
        %Account{id: account_id},
        %{amount: amount, date: date, through: through},
        opts \\ []
      ) do
    Sync.write(fn ->
      account = get_account!(scope, account_id)
      difference = amount - cleared_balance(scope, account, through)

      with :ok <- expect_difference(difference, Keyword.get(opts, :adjust, 0)),
           {:ok, adjustment} <- adjust(scope, account, difference, date) do
        {reconciled, _} =
          Sync.update_all(lockable(scope, account_id, through),
            set: [cleared: :reconciled, updated_at: DateTime.utc_now()]
          )

        Sync.update!(Changeset.change(account, last_reconciled_at: DateTime.utc_now()))
        {:ok, %{reconciled: reconciled, adjustment: adjustment && Repo.reload!(adjustment)}}
      end
    end)
  end

  defp expect_difference(expected, expected), do: :ok
  defp expect_difference(difference, _expected), do: {:error, {:difference, difference}}

  # Approval and a match decision change a transaction, so they come before its lock.
  defp lockable(scope, account_id, through),
    do:
      from(t in cleared_through(scope, account_id, through),
        where: t.cleared == :cleared and t.approved,
        where: t.id not in subquery(from p in proposals(scope), select: p.matched_transaction_id)
      )

  defp adjust(_scope, _account, 0, _date), do: {:ok, nil}

  defp adjust(scope, account, difference, date) do
    create_transaction(scope, %{
      account_id: account.id,
      date: date,
      amount: difference,
      payee_name: @adjustment_payee,
      category_id:
        if(Account.budget_account?(account), do: Categories.ready_to_assign!(scope).id),
      memo: @adjustment_memo,
      cleared: :cleared,
      approved: true
    })
  end

  @doc "Creates a regular payee; no other regular payee may have its lookup key."
  def create_payee(%Scope{} = scope, attrs) do
    %Payee{user_id: user_id(scope)}
    |> Payee.changeset(attrs)
    |> References.validate_exists(:last_category_id, owned(Category, scope))
    |> validate_unique_name(scope)
    |> Sync.insert()
  end

  def update_payee(%Scope{} = scope, %Payee{} = payee, attrs) do
    scope
    |> own!(payee)
    |> Payee.changeset(attrs)
    |> References.validate_exists(:last_category_id, owned(Category, scope))
    |> validate_unique_name(scope)
    |> Sync.update()
  end

  defp validate_unique_name(changeset, scope) do
    others =
      if id = changeset.data.id,
        do: from(p in regular_payees(scope), where: p.id != ^id),
        else: regular_payees(scope)

    with {:ok, key} <- Changeset.fetch_change(changeset, :lookup_key),
         true <- Repo.exists?(from p in others, where: p.lookup_key == ^key) do
      Changeset.add_error(changeset, :name, "has already been taken")
    else
      _unique -> changeset
    end
  end

  defp payees(scope), do: from(p in owned(Payee, scope), where: is_nil(p.deleted_at))

  defp regular_payees(scope), do: from(p in payees(scope), where: is_nil(p.transfer_account_id))

  @doc "The regular payees (no transfer payees) by name."
  def list_payees(%Scope{} = scope),
    do: Repo.all(from p in regular_payees(scope), order_by: [p.lookup_key, p.id])

  @doc "Finds a payee by name, ignoring emoji and case. Regular payees win over transfer payees."
  def find_payee_by_name(%Scope{} = scope, name) when is_binary(name) do
    key = Names.lookup_key(name)

    Repo.all(from p in payees(scope), where: p.lookup_key == ^key)
    |> Enum.map(&{&1, is_nil(&1.transfer_account_id)})
    |> Names.pick()
  end

  @doc """
  The account's transactions, or with `:all` every account's, newest first, with payee, category (and its group)
  and subtransactions; without deleted ones and match proposals, which count nowhere (see
  `list_match_proposals/2`).

  Options narrow the list: `filter: :unapproved` or `:uncleared` (`:all` for none), `ids:`, `without_accounts:`, the
  ids of accounts to leave out, and `limit:`, the newest so many.
  """
  def list_transactions(%Scope{} = scope, register, opts \\ []) do
    scope
    |> register(register)
    |> narrowed(opts)
    |> order_by([t], desc: t.date, desc: t.id)
    |> preload([
      :payee,
      :transfer_transaction,
      category: :category_group,
      subtransactions: [:payee, :transfer_transaction, category: :category_group]
    ])
    |> Repo.all()
  end

  @doc "How many transactions `list_transactions/3` lists with the same register and options."
  def count_transactions(%Scope{} = scope, register, opts \\ []),
    do: scope |> register(register) |> narrowed(opts) |> Repo.aggregate(:count)

  defp register(scope, %Account{id: account_id}),
    do: from(t in in_register(scope), where: t.account_id == ^account_id)

  defp register(scope, :all), do: in_register(scope)

  defp narrowed(query, opts), do: Enum.reduce(opts, query, &narrow(&2, &1))

  defp narrow(query, {:filter, :all}), do: query
  defp narrow(query, {:filter, :unapproved}), do: where(query, [t], not t.approved)
  defp narrow(query, {:filter, :uncleared}), do: where(query, [t], t.cleared == :uncleared)
  # One JSON parameter, as SQLite takes at most 32766 variables and a selection can hold more ids.
  defp narrow(query, {:ids, ids}),
    do:
      where(
        query,
        [t],
        fragment("? IN (SELECT value FROM json_each(?))", t.id, ^JSON.encode!(ids))
      )

  defp narrow(query, {:without_accounts, ids}), do: where(query, [t], t.account_id not in ^ids)
  defp narrow(query, {:limit, limit}), do: limit(query, ^limit)

  @doc """
  The category last used on a transfer between a budget account and the account of `transfer_payee_id`: on the
  newest transaction or subtransaction in the budget account's register with that transfer payee and a category.
  """
  def last_transfer_category_id(%Scope{} = scope, budget_account_id, transfer_payee_id) do
    transaction =
      Repo.one(
        from t in in_register(scope),
          where:
            t.account_id == ^budget_account_id and t.payee_id == ^transfer_payee_id and
              not is_nil(t.category_id),
          order_by: [desc: t.date, desc: t.id],
          limit: 1,
          select: {t.date, t.id, t.category_id}
      )

    subtransaction =
      Repo.one(
        from s in parts(),
          join: t in ^in_register(scope),
          on: t.id == s.transaction_id,
          where:
            t.account_id == ^budget_account_id and s.payee_id == ^transfer_payee_id and
              not is_nil(s.category_id),
          order_by: [desc: t.date, desc: t.id],
          limit: 1,
          select: {t.date, t.id, s.category_id}
      )

    case Enum.reject([transaction, subtransaction], &is_nil/1) do
      [] ->
        nil

      found ->
        found
        |> Enum.max_by(fn {date, id, _} -> {Date.to_gregorian_days(date), id} end)
        |> elem(2)
    end
  end

  @doc """
  The account's pending match proposals, or with `:all` every account's, newest first, with what the register
  shows of them and the transactions they would merge into (with payee and counterparts); options as for
  `list_transactions/3`.
  """
  def list_match_proposals(scope, register, opts \\ [])

  def list_match_proposals(%Scope{} = scope, %Account{id: account_id}, opts),
    do: list_proposals(from(t in proposals(scope), where: t.account_id == ^account_id), opts)

  def list_match_proposals(%Scope{} = scope, :all, opts),
    do: list_proposals(proposals(scope), opts)

  defp proposals(scope),
    do:
      from(t in owned(Transaction, scope),
        where: is_nil(t.deleted_at) and not is_nil(t.matched_transaction_id)
      )

  defp list_proposals(query, opts) do
    Repo.all(
      from t in narrowed(query, opts),
        order_by: [desc: t.date, desc: t.id],
        preload: [
          :payee,
          :subtransactions,
          category: :category_group,
          matched_transaction: [
            :payee,
            :transfer_transaction,
            subtransactions: :transfer_transaction
          ]
        ]
    )
  end

  @doc """
  The register transactions that imports from `source` look like, one per import (nil for none) in their order:
  in the account with the same amount, dated within 10 days, the closest pairs first and on a tie the older
  transaction (see `Abakus.Ledger.Matches.pick/3`). Each is matched once, and only while it is not reconciled, has
  no open proposal and no external id from `source` yet, but for the pending one of an approved transaction
  (ADR 0022). An open proposal of an unapproved pending import from `source` makes way for an import that is not
  pending (`yield_proposal/3`). Imports are maps with `:date`, `:amount` and optionally `:external_id`.
  """
  def find_matches(%Scope{}, %Account{}, _source, []), do: []

  def find_matches(%Scope{} = scope, %Account{id: account_id}, source, imports) do
    {first, last} = imports |> Enum.map(& &1.date) |> Enum.min_max_by(&Date.to_gregorian_days/1)

    yielding =
      Repo.all(
        from p in yielding_proposals(scope, source),
          where: p.account_id == ^account_id,
          select: p.matched_transaction_id
      )
      |> MapSet.new()

    candidates =
      imports
      |> Enum.map(& &1.amount)
      |> Enum.uniq()
      |> in_chunks(fn amounts ->
        Repo.all(
          from t in in_register(scope),
            where:
              t.account_id == ^account_id and t.cleared != :reconciled and t.amount in ^amounts and
                t.date >= ^Date.add(first, -Matches.days()) and
                t.date <= ^Date.add(last, Matches.days()),
            where:
              t.id not in subquery(
                from p in proposals(scope),
                  where: p.approved or p.id not in subquery(pending_imports(source)),
                  select: p.matched_transaction_id
              ),
            where:
              t.id not in subquery(
                from o in TransactionOrigin,
                  where: o.source == ^source and not pending?(o.external_id),
                  select: o.transaction_id
              ),
            where:
              t.approved or
                t.id not in subquery(
                  from o in TransactionOrigin,
                    where: o.source == ^source,
                    select: o.transaction_id
                ),
            preload: :payee
        )
      end)

    Matches.pick(imports, candidates, &(not (pending_import?(&1) and &2.id in yielding)))
  end

  defp pending_import?(import),
    do: String.starts_with?(import[:external_id] || "", TransactionOrigin.pending_prefix())

  defp yielding_proposals(scope, source),
    do:
      from(p in proposals(scope),
        where: not p.approved and p.id in subquery(pending_imports(source))
      )

  defp pending_imports(source),
    do:
      from(o in TransactionOrigin,
        where: o.source == ^source and pending?(o.external_id),
        select: o.transaction_id
      )

  @doc """
  Makes way for an import's proposal onto the transaction: the open proposal onto it of an unapproved pending import
  from `source` becomes an ordinary import again, which goes once the bank no longer reports it (ADR 0022).
  """
  def yield_proposal(%Scope{} = scope, %Transaction{id: id}, source) do
    Sync.update_all(
      from(p in yielding_proposals(scope, source), where: p.matched_transaction_id == ^id),
      set: [matched_transaction_id: nil, updated_at: DateTime.utc_now()]
    )

    :ok
  end

  @doc "The date of the newest reconciled transaction in the account's register, nil without one."
  def last_reconciled_date(%Scope{} = scope, %Account{id: account_id}) do
    Repo.one(
      from t in in_register(scope),
        where: t.account_id == ^account_id and t.cleared == :reconciled,
        select: max(t.date)
    )
  end

  @doc """
  A transaction with what the transaction form needs: payee, counterpart (and for the counterpart of a split's
  transfer the subtransaction it belongs to) and the subtransactions with their payees and counterparts.
  """
  def get_transaction!(%Scope{} = scope, id),
    do: Transaction |> owned(scope) |> Repo.get!(id) |> preload_for_form()

  @doc "Like `get_transaction!/2`, but nil for an id that is no transaction."
  def get_transaction(%Scope{} = scope, id) do
    with {:ok, id} <- Ids.cast(id),
         %Transaction{} = transaction <- Repo.get(owned(Transaction, scope), id) do
      preload_for_form(transaction)
    else
      _none -> nil
    end
  end

  defp preload_for_form(transaction) do
    Repo.preload(transaction, [
      :payee,
      :transfer_transaction,
      :transfer_subtransaction,
      subtransactions: [:payee, :transfer_transaction]
    ])
  end

  @doc "Transactions in the register, which count for listings and balances: not deleted and no match proposal."
  def in_register(%Scope{} = scope) do
    from t in owned(Transaction, scope),
      where: is_nil(t.deleted_at) and is_nil(t.matched_transaction_id)
  end

  @doc "The account's balance up to and including `through`: the sum of its transactions in the register dated so."
  def balance(%Scope{} = scope, %Account{id: account_id}, %Date{} = through) do
    Repo.one(
      from t in in_register(scope),
        where: t.account_id == ^account_id and t.date <= ^through,
        select: coalesce(sum(t.amount), 0)
    )
  end

  @doc """
  Each account's balance up to and including `through` by account id, as `balance/3`; accounts without any are
  missing.
  """
  def balances_through(%Scope{} = scope, %Date{} = through) do
    Repo.all(
      from t in in_register(scope),
        where: t.date <= ^through,
        group_by: t.account_id,
        select: {t.account_id, sum(t.amount)}
    )
    |> Map.new()
  end

  @doc """
  Net worth at the end of each day of `range`, as `[{date, cents}]`: the balance of all accounts, budget and
  tracking, but those closed with money left in them, unless their ids are in `kept`.
  """
  def net_worth(%Scope{} = scope, %Date.Range{first: first, last: last} = range, kept \\ []) do
    open = counted_in_net_worth(scope, kept)

    opening =
      Repo.one(from t in open, where: t.date < ^first, select: coalesce(sum(t.amount), 0))

    by_day =
      Repo.all(
        from t in open,
          where: t.date >= ^first and t.date <= ^last,
          group_by: t.date,
          select: {t.date, sum(t.amount)}
      )
      |> Map.new()

    range
    |> Enum.map_reduce(opening, fn date, total ->
      total = total + Map.get(by_day, date, 0)
      {{date, total}, total}
    end)
    |> elem(0)
  end

  @doc "The date of the first transaction that counts toward net worth (see `net_worth/3`), nil without any."
  def first_open_date(%Scope{} = scope, kept \\ []),
    do: Repo.one(from t in counted_in_net_worth(scope, kept), select: min(t.date))

  defp counted_in_net_worth(scope, kept) do
    left_with_money =
      from t in in_register(scope),
        join: a in assoc(t, :account),
        where: a.closed and a.id not in ^kept,
        group_by: t.account_id,
        having: sum(t.amount) != 0,
        select: t.account_id

    from t in in_register(scope), where: t.account_id not in subquery(left_with_money)
  end

  @doc """
  Each account's register as `%{balance, cleared, uncleared, unapproved}` by account id; cleared counts reconciled
  transactions too, unapproved is how many wait for approval, match proposals included. Accounts without
  transactions are missing.
  """
  def balances(%Scope{} = scope) do
    Repo.all(
      from t in owned(Transaction, scope),
        where: is_nil(t.deleted_at),
        group_by: t.account_id,
        select:
          {t.account_id,
           %{
             balance: coalesce(filter(sum(t.amount), is_nil(t.matched_transaction_id)), 0),
             cleared:
               coalesce(
                 filter(
                   sum(t.amount),
                   is_nil(t.matched_transaction_id) and t.cleared != :uncleared
                 ),
                 0
               ),
             uncleared:
               coalesce(
                 filter(
                   sum(t.amount),
                   is_nil(t.matched_transaction_id) and t.cleared == :uncleared
                 ),
                 0
               ),
             unapproved: filter(count(t.id), not t.approved)
           }}
    )
    |> Map.new()
  end

  @doc """
  What the budget accounts' register adds up to per `{category_id, month}` (the month's first day): a split by its
  subtransactions, a transaction or subtransaction without a category under `nil`, unless it is a transfer
  (between budget accounts, which have none). Tracking accounts do not count.
  """
  def budget_activity(%Scope{} = scope) do
    transactions =
      from t in in_register(scope),
        join: a in assoc(t, :account),
        where: a.kind in ^Account.budget_kinds(),
        where: t.id not in subquery(from s in parts(), select: s.transaction_id),
        where:
          not is_nil(t.category_id) or
            (is_nil(t.transfer_transaction_id) and is_nil(t.transfer_subtransaction_id)),
        group_by: [t.category_id, month(t.date)],
        select: {{t.category_id, month(t.date)}, sum(t.amount)}

    subtransactions =
      from s in parts(),
        join: t in subquery(in_register(scope)),
        on: t.id == s.transaction_id,
        join: a in Account,
        on: a.id == t.account_id,
        where: a.kind in ^Account.budget_kinds(),
        where: not is_nil(s.category_id) or is_nil(s.transfer_transaction_id),
        group_by: [s.category_id, month(t.date)],
        select: {{s.category_id, month(t.date)}, sum(s.amount)}

    sum_by_key(Repo.all(transactions) ++ Repo.all(subtransactions))
  end

  @doc "Whether a reconciled transaction, not deleted, has the category, itself or in a split line."
  def reconciled_in_category?(%Scope{} = scope, category_id) do
    Repo.exists?(
      from t in owned(Transaction, scope),
        left_join: s in Subtransaction,
        on: s.transaction_id == t.id and is_nil(s.deleted_at),
        where: t.cleared == :reconciled and is_nil(t.deleted_at),
        where: t.category_id == ^category_id or s.category_id == ^category_id
    )
  end

  @doc """
  Points everything that has the category `from_id` to `to_id`: transactions and split lines, deleted ones and match
  proposals included, scheduled transactions with their parts, and payees' last categories. Reconciled transactions
  among them need `reconciled: :confirmed` (see `reconciled_in_category?/2`).
  """
  def recategorize(%Scope{} = scope, from_id, to_id, opts \\ []) do
    if Keyword.get(opts, :reconciled) != :confirmed and reconciled_in_category?(scope, from_id),
      do: {:error, :reconciled},
      else: move_category(scope, from_id, to_id)
  end

  defp move_category(scope, from_id, to_id) do
    now = DateTime.utc_now()
    transaction_ids = select(owned(Transaction, scope), [t], t.id)

    splits =
      from s in Subtransaction,
        where: s.category_id == ^from_id and s.transaction_id in subquery(transaction_ids),
        select: s.transaction_id

    Repo.update_all(from(t in Transaction, where: t.id in subquery(splits)),
      set: [updated_at: now]
    )

    set = [set: [category_id: to_id, updated_at: now]]
    scheduled_ids = select(owned(ScheduledTransaction, scope), [s], s.id)

    Sync.update_all(
      from(s in Subtransaction,
        where: s.category_id == ^from_id and s.transaction_id in subquery(transaction_ids)
      ),
      set
    )

    Sync.update_all(from(t in owned(Transaction, scope), where: t.category_id == ^from_id), set)

    Sync.update_all(
      from(s in owned(ScheduledTransaction, scope), where: s.category_id == ^from_id),
      set
    )

    Sync.update_all(
      from(s in ScheduledSubtransaction,
        where: s.category_id == ^from_id and s.scheduled_transaction_id in subquery(scheduled_ids)
      ),
      set
    )

    Sync.update_all(from(p in owned(Payee, scope), where: p.last_category_id == ^from_id),
      set: [last_category_id: to_id, updated_at: now]
    )

    :ok
  end

  defp parts, do: from(s in Subtransaction, where: is_nil(s.deleted_at))

  @doc """
  Merges the regular payees `ids` that share their lookup key with other regular payees, and those, into the oldest
  of them, the one with the smallest id: what pointed at a merged payee points at that one, which takes the merged
  one's last category if it has none, and the merged payee is deleted with it as its successor.
  """
  def merge_duplicate_payees(%Scope{} = scope, ids) do
    keys =
      Repo.all(
        from p in regular_payees(scope), where: p.id in ^ids, select: p.lookup_key, distinct: true
      )

    Enum.each(keys, fn key ->
      [into | merged] =
        Repo.all(from p in regular_payees(scope), where: p.lookup_key == ^key, order_by: p.id)

      Enum.reduce(merged, into, &merge_payee(scope, &1, &2))
    end)
  end

  defp merge_payee(scope, %Payee{id: from_id} = from, %Payee{id: into_id} = into) do
    repoint_payee(scope, from_id, into_id)
    Sync.update!(Changeset.change(from, deleted_at: DateTime.utc_now(), successor_id: into_id))

    if is_nil(into.last_category_id) and from.last_category_id,
      do: Sync.update!(Changeset.change(into, last_category_id: from.last_category_id)),
      else: into
  end

  @doc """
  Points what points at the payees `ids` that are merged at the end of their chains of successors
  (`Abakus.Successors`), as merging them did, for references set to a payee after it was merged.
  """
  def follow_merged_payees(%Scope{} = scope, ids) do
    successors = Successors.of(scope, Payee)

    for id <- Enum.uniq(ids),
        into_id = Map.get(successors, id, id),
        into_id != id,
        do: repoint_payee(scope, id, into_id)

    :ok
  end

  defp repoint_payee(scope, from_id, into_id) do
    set = [set: [payee_id: into_id, updated_at: DateTime.utc_now()]]

    Sync.update_all(from(t in owned(Transaction, scope), where: t.payee_id == ^from_id), set)
    Sync.update_all(from(s in Subtransaction, where: s.payee_id == ^from_id), set)

    Sync.update_all(
      from(s in owned(ScheduledTransaction, scope), where: s.payee_id == ^from_id),
      set
    )

    Sync.update_all(from(s in ScheduledSubtransaction, where: s.payee_id == ^from_id), set)

    Sync.update_all(
      from(c in owned(PayeeRenameCondition, scope), where: c.payee_id == ^from_id),
      set
    )
  end

  defp sum_by_key(pairs) do
    pairs
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Map.new(fn {key, amounts} -> {key, Enum.sum(amounts)} end)
  end

  @doc """
  Creates a transaction, with subtransactions for a split. Checks the references and the rules for the accounts
  involved (`Transaction.validate_accounts/4`) and keeps the counterparts of transfers (`Abakus.Ledger.Transfers`).
  Approval defaults by source: manual entries are approved, imports and the Kasse's are not. Categories are
  remembered as their payees' last categories.

  Instead of `payee_id`, `payee_name` names the payee, also in a subtransaction: the regular payee with that lookup
  key, else a new one; a blank name means none. A refused write creates no payee. `led_by:` names the source the
  transaction refers to, `entered_from: {scheduled_transaction_id, date}` the occurrence of a scheduled
  transaction it is entered as.
  """
  def create_transaction(%Scope{} = scope, attrs, opts \\ []) do
    references = if led_by = opts[:led_by], do: Transaction.source_reference(led_by), else: %{}

    Sync.write(fn ->
      with {:ok, attrs} <- put_payee_by_name(scope, attrs) do
        %Transaction{user_id: user_id(scope)}
        |> struct!(references)
        |> struct!(entered_from(opts[:entered_from]))
        |> Transaction.changeset(attrs)
        |> put_entered_part_ids()
        |> put_default_approval()
        |> write(&Sync.insert/1, opts)
      end
    end)
  end

  # Every writer enters an occurrence with the same parts.
  defp put_entered_part_ids(
         %Changeset{data: %Transaction{scheduled_transaction_id: nil}} = changeset
       ),
       do: changeset

  defp put_entered_part_ids(%Changeset{data: %Transaction{id: id}} = changeset) do
    Transaction.update_subtransactions(changeset, fn part ->
      Changeset.put_change(
        part,
        :id,
        Ids.entered_subtransaction(id, Changeset.get_field(part, :position))
      )
    end)
  end

  defp entered_from(nil), do: %{}

  defp entered_from({scheduled_transaction_id, date}) do
    %{
      id: Ids.entered_transaction(scheduled_transaction_id, date),
      scheduled_transaction_id: scheduled_transaction_id,
      scheduled_date: date
    }
  end

  defp put_payee_by_name(scope, attrs) do
    with {:ok, attrs} <- put_own_payee(scope, attrs) do
      put_subtransaction_payees(scope, attrs)
    end
  end

  defp put_own_payee(scope, %{payee_name: name} = attrs),
    do: put_payee(scope, attrs, :payee_name, name)

  defp put_own_payee(scope, %{"payee_name" => name} = attrs),
    do: put_payee(scope, attrs, "payee_name", name)

  defp put_own_payee(_scope, attrs), do: {:ok, attrs}

  defp put_subtransaction_payees(scope, %{subtransactions: [_ | _] = subtransactions} = attrs) do
    subtransactions
    |> Enum.reduce_while({:ok, []}, fn subtransaction, {:ok, done} ->
      case put_own_payee(scope, subtransaction) do
        {:ok, subtransaction} -> {:cont, {:ok, [subtransaction | done]}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, done} -> {:ok, %{attrs | subtransactions: Enum.reverse(done)}}
      error -> error
    end
  end

  defp put_subtransaction_payees(_scope, attrs), do: {:ok, attrs}

  defp put_payee(scope, attrs, key, name) do
    id_key = if is_atom(key), do: :payee_id, else: "payee_id"

    with {:ok, payee} <- payee_named(scope, String.trim(name || "")) do
      {:ok, attrs |> Map.delete(key) |> Map.put(id_key, payee && payee.id)}
    end
  end

  defp payee_named(_scope, ""), do: {:ok, nil}

  defp payee_named(scope, name) do
    key = Names.lookup_key(name)

    case Repo.one(from p in regular_payees(scope), where: p.lookup_key == ^key) do
      nil -> create_payee(scope, %{name: name})
      payee -> {:ok, payee}
    end
  end

  defp put_default_approval(changeset) do
    manual? = Changeset.get_field(changeset, :source) == :manual

    if Map.has_key?(changeset.params, "approved"),
      do: changeset,
      else: Changeset.put_change(changeset, :approved, manual?)
  end

  @doc """
  Updates a transaction as stored (the struct only names it) and its counterparts. A deleted transaction cannot
  be changed; the counterpart of a split's subtransaction changes only its own fields (cleared, approved,
  category), the rest in its split. When the account changes, the origins move along. A change that alters a
  reconciled transaction or counterpart needs `reconciled: :confirmed`, one of the `led_fields/0` of a led
  transaction its source (`led_by:`). The payee may be given by name, as for `create_transaction/3`.
  """
  def update_transaction(%Scope{} = scope, %Transaction{id: id}, attrs, opts \\ []) do
    Sync.write(fn ->
      with {:ok, attrs} <- put_payee_by_name(scope, attrs) do
        Transaction
        |> owned(scope)
        |> Repo.get!(id)
        |> Repo.preload(:subtransactions)
        |> Transaction.changeset(attrs)
        |> write(&Sync.update/1, opts)
      end
    end)
  end

  @doc """
  Applies the same change to several transactions with `update_transaction/4`, all or none: the first refusal
  stops and returns its changeset.
  """
  def update_transactions(%Scope{} = scope, transactions, attrs, opts \\ []) do
    Sync.write(fn ->
      all_or_none(transactions, &update_transaction(scope, &1, attrs, opts))
    end)
  end

  defp all_or_none(transactions, fun) do
    transactions
    |> Enum.reduce_while({:ok, []}, &apply_next(&1, &2, fun))
    |> case do
      {:ok, done} -> {:ok, Enum.reverse(done)}
      error -> error
    end
  end

  defp apply_next(transaction, {:ok, done}, fun) do
    case fun.(transaction) do
      {:ok, transaction} -> {:cont, {:ok, [transaction | done]}}
      error -> {:halt, error}
    end
  end

  defp write(changeset, save, opts) do
    context = context(changeset, opts)

    changeset
    |> validate_references(context.user_id)
    |> Matches.validate(context.leading?)
    |> validate_accounts(context)
    |> validate_reconciled(context.confirmed?)
    |> validate_led(context)
    |> save(save, context)
  end

  # The changeset's user, from a new transaction's struct or the stored one, owns everything it may point to.
  defp context(changeset, opts) do
    sides = [changeset | Transaction.subtransactions(changeset)]
    user_id = Changeset.get_field(changeset, :user_id)
    account_id = Changeset.get_field(changeset, :account_id)
    counterpart_ids = Enum.map(sides, &Changeset.get_field(&1, :transfer_transaction_id))
    counterparts = Transfers.by_id(counterpart_ids)
    led_by = source(changeset.data, counterparts[changeset.data.transfer_transaction_id])

    %{
      user_id: user_id,
      account: account_id && Repo.get_by(Account, id: account_id, user_id: user_id),
      transfer_accounts:
        Transfers.accounts_by_payee(
          user_id,
          Enum.map(sides, &Changeset.get_field(&1, :payee_id))
        ),
      counterparts: counterparts,
      confirmed?: Keyword.get(opts, :reconciled) == :confirmed,
      led_by: led_by,
      writer: opts[:led_by],
      leading?: not is_nil(led_by) and led_by == opts[:led_by]
    }
  end

  defp validate_references(changeset, user_id) do
    sides = [changeset | Transaction.subtransactions(changeset)]

    payees =
      References.existing(
        from(p in Payee, where: p.user_id == ^user_id),
        changed_ids(sides, :payee_id)
      )

    categories =
      References.existing(
        from(c in Category, where: c.user_id == ^user_id),
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

  @reconciled "ist abgeglichen"
  @counterpart_reconciled "betrifft eine abgeglichene Gegenbuchung"

  # The counterpart's category is checked where it would change.
  defp validate_reconciled(
         %Changeset{data: %Transaction{cleared: :reconciled}} = changeset,
         false
       ) do
    if Map.delete(changeset.changes, :counterpart_category_id) == %{},
      do: changeset,
      else: Changeset.add_error(changeset, :cleared, @reconciled, reconciled: true)
  end

  defp validate_reconciled(changeset, _confirmed?), do: changeset

  @led_fields [:account_id, :date, :amount, :payee_id, :subtransactions]

  @doc "The fields a transaction's source leads (`led_by/2`); `payee_name` gives the payee too."
  def led_fields, do: @led_fields

  @doc """
  The source that leads a transaction, its own or its transfer counterpart's: `{:kasse_expense, id}`,
  `{:depot_transaction, id}` or nil.
  """
  def led_by(%Scope{} = scope, %Transaction{id: id}) do
    transaction = Repo.get!(owned(Transaction, scope), id)

    counterpart =
      transaction.transfer_transaction_id &&
        Repo.get(Transaction, transaction.transfer_transaction_id)

    source(transaction, counterpart)
  end

  defp source(transaction, counterpart),
    do: Transaction.led_by(transaction) || (counterpart && Transaction.led_by(counterpart))

  @doc """
  Puts a source on a transaction no source leads yet, itself or through its counterpart, such as a transfer booked in
  the register that becomes a Kasse reimbursement; the source leads it from then on (`led_by/2`).
  """
  def lead(%Scope{} = scope, %Transaction{id: id}, led_by) do
    transaction = Repo.get!(owned(Transaction, scope), id)
    changeset = Transaction.reference_changeset(transaction, led_by)

    cond do
      transaction.deleted_at ->
        {:error, failed(changeset, :deleted_at, "Die Buchung ist gelöscht")}

      leading = led_by(scope, transaction) ->
        {:error, failed(changeset, :led_by, follows(leading))}

      true ->
        Sync.update(changeset)
    end
  end

  defp validate_led(changeset, %{led_by: led_by, writer: writer})
       when is_nil(led_by) or led_by == writer,
       do: changeset

  defp validate_led(changeset, %{led_by: led_by}) do
    Enum.reduce(@led_fields, changeset, fn field, changeset ->
      if Map.has_key?(changeset.changes, field),
        do: Changeset.add_error(changeset, field, follows(led_by)),
        else: changeset
    end)
  end

  defp follows({:kasse_expense, _id}), do: "folgt der Ausgabe in der Kasse"
  defp follows({:depot_transaction, _id}), do: "folgt der Buchung im Depot"

  defp deleted_with({:kasse_expense, _id}), do: "wird mit ihrer Ausgabe in der Kasse gelöscht"
  defp deleted_with({:depot_transaction, _id}), do: "wird mit ihrer Buchung im Depot gelöscht"

  @origin_taken "enthält diese Buchung schon aus derselben Quelle"
  @counterpart_origin_taken "führt in ein Konto, das diese Buchung schon aus derselben Quelle enthält"

  defp save(changeset, save, context) do
    with :ok <- release_removed(changeset, context),
         :ok <- dissolve_moved_proposals(changeset, context),
         {changeset, removed} = Transaction.take_removed_subtransactions(changeset),
         {:ok, transaction} <- save.(changeset),
         :ok <- delete_parts(removed),
         :ok <- move_origins(changeset, transaction),
         {:ok, transaction} <- sync(changeset, transaction, context) do
      remember_categories(transaction)
      {:ok, transaction}
    end
  end

  defp dissolve_moved_proposals(%Changeset{data: %Transaction{id: id}} = changeset, %{
         leading?: true
       })
       when not is_nil(id) do
    if Changeset.changed?(changeset, :account_id) or Changeset.changed?(changeset, :amount),
      do: Matches.dissolve(id),
      else: :ok
  end

  defp dissolve_moved_proposals(_changeset, _context), do: :ok

  defp release_removed(changeset, context) do
    case Transfers.release_removed(changeset, context.confirmed?) do
      :ok ->
        :ok

      {:error, {:reconciled, _field}} ->
        {:error, failed(changeset, :subtransactions, @counterpart_reconciled, reconciled: true)}
    end
  end

  defp delete_parts([]), do: :ok

  defp delete_parts(ids) do
    Sync.delete_all(from s in Subtransaction, where: s.id in ^ids)
    :ok
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

      {:error, {:reconciled, field}} ->
        {:error,
         sync_failed(changeset, transaction, field, @counterpart_reconciled, reconciled: true)}

      synced ->
        synced
    end
  end

  # The rest follow the same field; a split's counterparts follow its subtransactions, but for the date.
  @follows %{account_id: :payee_id, payee_id: :account_id, category_id: :counterpart_category_id}

  defp sync_failed(changeset, transaction, counterpart_field, message, opts \\ []) do
    field =
      cond do
        counterpart_field == :date -> :date
        transaction.subtransactions != [] -> :subtransactions
        true -> Map.get(@follows, counterpart_field, counterpart_field)
      end

    failed(changeset, field, message, opts)
  end

  defp failed(changeset, field, message, opts \\ []),
    do: %{Changeset.add_error(changeset, field, message, opts) | action: :update}

  # A match proposal is no booking yet, so it leaves the payee alone.
  defp remember_categories(%Transaction{matched_transaction_id: id}) when not is_nil(id), do: :ok

  defp remember_categories(transaction) do
    for %{payee_id: payee_id, category_id: category_id} <- [
          transaction | transaction.subtransactions
        ],
        payee_id && category_id do
      Sync.update_all(
        from(p in Payee,
          where:
            p.id == ^payee_id and is_nil(p.transfer_account_id) and
              (is_nil(p.last_category_id) or p.last_category_id != ^category_id)
        ),
        set: [last_category_id: category_id, updated_at: DateTime.utc_now()]
      )
    end
  end

  @doc """
  Soft-deletes a transaction with every transfer counterpart: deleting either side of a transfer deletes both,
  deleting a split deletes the counterparts of its subtransactions. The counterpart of a subtransaction is
  deleted with its split, so deleting it on its own is refused. Deleting a deleted transaction changes nothing.
  Deleting a reconciled transaction, or one with a reconciled counterpart, needs `reconciled: :confirmed`, deleting a
  led one its source (`led_by:`).
  """
  def delete_transaction(%Scope{} = scope, %Transaction{id: id}, opts \\ []) do
    confirmed? = Keyword.get(opts, :reconciled) == :confirmed

    Sync.write(fn ->
      transaction = Transaction |> owned(scope) |> Repo.get!(id) |> Repo.preload(:subtransactions)

      with :ok <- check_writer(scope, transaction, opts[:led_by]),
           do: soft_delete(transaction, confirmed?)
    end)
  end

  defp check_writer(_scope, %Transaction{deleted_at: %DateTime{}}, _writer), do: :ok

  defp check_writer(scope, transaction, writer) do
    case led_by(scope, transaction) do
      led_by when is_nil(led_by) or led_by == writer -> :ok
      led_by -> delete_failed(transaction, :led_by, deleted_with(led_by))
    end
  end

  defp soft_delete(transaction, confirmed?) do
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
        delete_failed(transaction, :cleared, @reconciled, reconciled: true)

      not confirmed? and Transfers.reconciled?(ids) ->
        delete_failed(transaction, pair_field(transaction), @counterpart_reconciled,
          reconciled: true
        )

      true ->
        Transfers.soft_delete(ids)
        {:ok, Transaction |> Repo.get!(transaction.id) |> Repo.preload(:subtransactions)}
    end
  end

  @doc "Deletes several transactions with `delete_transaction/3`, all or none: the first refusal stops."
  def delete_transactions(%Scope{} = scope, transactions, opts \\ []) do
    Sync.write(fn -> all_or_none(transactions, &delete_transaction(scope, &1, opts)) end)
  end

  defp pair_field(%Transaction{subtransactions: []}), do: :transfer_transaction_id
  defp pair_field(_split), do: :subtransactions

  defp delete_failed(transaction, field, message, opts \\ []) do
    {:error,
     transaction
     |> Changeset.change()
     |> Changeset.add_error(field, message, opts)
     |> Map.put(:action, :delete)}
  end

  # Pointers are symmetric (the Ledger alone sets them), so these are all sides involved.
  defp pair_ids(transaction) do
    ids = Enum.map([transaction | transaction.subtransactions], & &1.transfer_transaction_id)
    Enum.reject([transaction.id | ids], &is_nil/1)
  end

  @doc """
  Accepts a match proposal: the existing transaction survives with its id, payee and amount, keeps its category
  and memo where it has them (else takes the import's), takes the import's date (unless a split or a source owns
  it) and cleared state, is approved and gets the import's origins; the proposal is removed, so one a source leads is
  refused. The rules for a new proposal are checked again, so a transaction reconciled meanwhile refuses it. `opts`
  go to `update_transaction/4`.
  """
  def accept_match(%Scope{} = scope, %Transaction{id: id}, opts \\ []) do
    Sync.write(fn ->
      with {:ok, proposal} <- pending_proposal(scope, id),
           :ok <- check_writer(scope, proposal, nil),
           existing = Repo.get(owned(Transaction, scope), proposal.matched_transaction_id),
           :ok <- check_match(proposal, existing),
           :ok <- take_origins(proposal, existing) do
        Transfers.soft_delete([proposal.id])
        update_transaction(scope, existing, merged(scope, existing, proposal), opts)
      end
    end)
  end

  defp merged(scope, existing, proposal) do
    merged = Matches.merged(Repo.preload(existing, :subtransactions), proposal)
    if led_by(scope, existing), do: Map.drop(merged, @led_fields), else: merged
  end

  @doc "Accepts several match proposals with `accept_match/3`, all or none: the first refusal stops."
  def accept_matches(%Scope{} = scope, proposals, opts \\ []) do
    Sync.write(fn -> all_or_none(proposals, &accept_match(scope, &1, opts)) end)
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
  def reject_match(%Scope{} = scope, %Transaction{id: id}) do
    Sync.write(fn ->
      with {:ok, proposal} <- pending_proposal(scope, id) do
        proposal |> Changeset.change(matched_transaction_id: nil, approved: true) |> Sync.update()
      end
    end)
  end

  defp pending_proposal(scope, id) do
    case Repo.get(owned(Transaction, scope), id) do
      %Transaction{deleted_at: nil, matched_transaction_id: matched} = proposal
      when not is_nil(matched) ->
        {:ok, proposal}

      _transaction ->
        {:error, :not_a_proposal}
    end
  end

  @doc "Records where a transaction was imported from; the account is the one the transaction is in now."
  def add_origin(%Scope{} = scope, %Transaction{id: id}, source, external_id) do
    case Repo.one(from t in owned(Transaction, scope), where: t.id == ^id, select: t.account_id) do
      nil ->
        changeset = Changeset.change(%TransactionOrigin{transaction_id: id})
        {:error, %{References.not_found(changeset, :transaction_id) | action: :insert}}

      account_id ->
        %TransactionOrigin{transaction_id: id, account_id: account_id, user_id: user_id(scope)}
        |> TransactionOrigin.changeset(%{source: source, external_id: external_id})
        |> Repo.insert()
    end
  end

  @doc "Which of `external_ids` the account has from `source`, deleted transactions and proposals included."
  def existing_external_ids(%Scope{} = scope, %Account{id: account_id}, source, external_ids) do
    external_ids
    |> in_chunks(fn external_ids ->
      Repo.all(
        from o in owned(TransactionOrigin, scope),
          where:
            o.account_id == ^account_id and o.source == ^source and
              o.external_id in ^external_ids,
          select: o.external_id
      )
    end)
    |> MapSet.new()
  end

  @doc """
  The account's pending imports from `source` dated from `from` on that are still unapproved, neither deleted nor
  reconciled, with their external ids: `[{external_id, transaction}]`.
  """
  def list_pending_imports(%Scope{} = scope, %Account{id: account_id}, source, %Date{} = from) do
    Repo.all(
      from t in owned(Transaction, scope),
        join: o in assoc(t, :origins),
        where:
          t.account_id == ^account_id and is_nil(t.deleted_at) and not t.approved and
            t.cleared != :reconciled and t.date >= ^from,
        where: o.account_id == ^account_id and o.source == ^source and pending?(o.external_id),
        order_by: t.id,
        select: {o.external_id, t}
    )
  end

  # SQLite takes at most 32766 variables in a statement.
  defp in_chunks(values, query),
    do: values |> Enum.chunk_every(1000) |> Enum.flat_map(query)

  @doc "The transaction an external id was imported as or matched to, deleted ones and proposals included."
  def get_transaction_by_origin(%Scope{} = scope, %Account{id: account_id}, source, external_id) do
    Repo.one(
      from t in owned(Transaction, scope),
        join: o in assoc(t, :origins),
        where:
          o.account_id == ^account_id and o.source == ^source and o.external_id == ^external_id
    )
  end
end
