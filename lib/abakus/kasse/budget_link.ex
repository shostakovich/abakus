defmodule Abakus.Kasse.BudgetLink do
  @moduledoc """
  Expenses and reimbursements linked to the budget (ADR 0020). A linked participant (the budget owner, once switched
  on) has what each expense changes in their Kasse balance, paid minus share, as a transaction in the shared-expenses
  account, so its balance is their Kasse balance. It is written through the Ledger with their scope in the
  expense's database transaction: dated as the expense, the title as payee, the budget category the Kasse category
  is mapped to, a memo describing the expense, created cleared and unapproved. Their bank purchase of an expense
  they paid stays a purchase in its category, which so bears only their share. Expenses that change nothing for them
  give none. An expense dated before the link's start date, if it has one, gets none unless it is entered after the
  switch or moved to a later date.

  A reimbursement that involves them is a transfer between that account and the budget account they choose for it
  (`reimbursement_accounts/1`), without category; until they choose one, it is a transaction in that account with
  the title as payee that still needs one. Money between them and the group can also start in the register
  (`write_from_register/4`).

  The transaction refers to its expense, which leads it: amount, date, payee and account follow every change of the
  expense, and the Ledger refuses them to anyone else. Category, memo, cleared state and approval are the register's;
  a later Kasse change keeps a memo the register changed, but a change of the Kasse category always writes the mapped
  category.

  The functions the link's page calls take the caller's scope; only the budget owner's may switch it on, choose the
  account or map the categories. Those the budget calls take its user's scope and see only what points into their
  budget. The link's tables stay out of the MCP's SQL sandbox, as they point into the budget.
  """

  import Ecto.Query

  alias Abakus.Categories.Category, as: BudgetCategory
  alias Abakus.Kasse
  alias Abakus.Kasse.{Access, AccessError, Expenses}
  alias Abakus.Kasse.BudgetLink.{CategoryMapping, Link}
  alias Abakus.Kasse.Categories.Category
  alias Abakus.Kasse.Expenses.Expense
  alias Abakus.Kasse.Participants.Participant
  alias Abakus.Ledger
  alias Abakus.Ledger.{Account, Matches, Payee, Subtransaction, Transaction}
  alias Abakus.Money
  alias Abakus.Repo
  alias Abakus.Users.{Scope, User}
  alias Ecto.Changeset

  @doc "The accounts a participant can be linked to: open budget accounts, in order."
  def account_choices(%Scope{} = scope) do
    owner!(scope)
    choices(scope)
  end

  defp choices(scope) do
    Repo.all(
      from a in Account,
        where: a.user_id == ^scope.user.id and a.kind in ^Account.budget_kinds() and not a.closed,
        order_by: [a.position, a.id]
    )
  end

  @doc """
  The accounts the scope's person can choose for a reimbursement, open budget accounts but the shared-expenses
  account, in order; none while they are not linked.
  """
  def reimbursement_accounts(%Scope{} = scope) do
    id = Access.person!(scope).id

    case Repo.one(
           from l in Link,
             join: a in assoc(l, :account),
             where: l.participant_id == ^id,
             select: a.user_id
         ) do
      nil -> []
      user_id -> reimbursement_accounts_of(user_id)
    end
  end

  defp reimbursement_accounts_of(user_id) do
    Repo.all(
      from a in Account,
        where:
          a.user_id == ^user_id and a.kind in ^Account.budget_kinds() and not a.closed and
            not a.shared_expenses,
        order_by: [a.position, a.id]
    )
  end

  @doc """
  Links the scope's person, the budget owner's participant, to the budget: the account `account_id` (one of
  `account_choices/1`) becomes the shared-expenses account, and every expense and reimbursement that changes their
  balance gets its transaction. Returns `{:ok, %{created: count}}` or `{:error, reason}`: `:not_budget_owner`,
  `:linked`, `:no_account` or a message in German.
  """
  def switch_on(%Scope{} = scope, account_id) do
    participant = Access.person!(scope)
    Repo.transact(fn -> link(scope, participant, account_id) end)
  end

  defp link(scope, participant, account_id) do
    with :ok <- check_linkable(scope, participant),
         {:ok, account} <- feed(scope, account_id) do
      %Link{participant_id: participant.id, account_id: account.id}
      |> Repo.insert!()
      |> book_all(scope)
    end
  end

  defp check_linkable(scope, participant) do
    cond do
      not Scope.budget_owner?(scope) -> {:error, :not_budget_owner}
      Repo.exists?(where(Link, participant_id: ^participant.id)) -> {:error, :linked}
      true -> :ok
    end
  end

  defp feed(scope, account_id) do
    with {:ok, id} <- Abakus.Ids.cast(account_id),
         %Account{} = account <- Enum.find(choices(scope), &(&1.id == id)) do
      Repo.update_all(
        from(a in Account,
          where: a.user_id == ^scope.user.id and a.shared_expenses and a.id != ^id
        ),
        set: [shared_expenses: false]
      )

      Ledger.update_account(scope, account, %{shared_expenses: true})
    else
      _none -> {:error, :no_account}
    end
  end

  defp book_all(link, scope) do
    from(e in Expense,
      where: is_nil(e.deleted_at),
      order_by: [e.date, e.id],
      preload: [:paid_by, :shares]
    )
    |> Repo.all()
    |> Enum.reduce_while({:ok, %{created: 0}}, fn expense, {:ok, %{created: count}} = booked ->
      case book(scope, link, expense) do
        :none -> {:cont, booked}
        :ok -> {:cont, {:ok, %{created: count + 1}}}
        {:error, %Changeset{} = changeset} -> {:halt, {:error, refused(changeset)}}
      end
    end)
  end

  defp book(scope, link, expense) do
    case wanted(expense, link, nil) do
      nil -> :none
      wanted -> create(scope, link, expense.id, wanted)
    end
  end

  @doc "The account the scope's person's expenses are booked in; nil while they are not linked."
  def account(%Scope{} = scope) do
    id = Access.person!(scope).id

    Repo.one(
      from l in Link, join: a in assoc(l, :account), where: l.participant_id == ^id, select: a
    )
  end

  @doc """
  Writes what a change of an expense means for the linked transactions, inside the caller's database transaction:
  `old` and `new` are the expense before and after (nil for none, both with payer and shares). For the link of the
  person `:by`, `:budget_account_id` chooses the account of a reimbursement (nil for none; left out, it stays), and
  `:adopt` is a transaction of the register that becomes the new expense's instead of a new one. Returns `:ok` or
  `{:error, message}`, in German.
  """
  def expense_written(old, new, opts \\ []) do
    links = Repo.all(from l in Link, order_by: l.participant_id, preload: :participant)

    Enum.reduce_while(links, :ok, fn link, :ok ->
      choice = if opts[:by] == link.participant_id, do: opts, else: []

      case write(Scope.for_participant(link.participant), link, old, new, choice) do
        :ok -> {:cont, :ok}
        {:error, %Changeset{} = changeset} -> {:halt, {:error, refused(changeset)}}
        {:error, message} -> {:halt, {:error, message}}
      end
    end)
  end

  defp write(scope, link, old, new, choice) do
    expense_id = (new || old).id
    linked = linked_transaction(scope, expense_id)
    current = linked && transfer_account_id(linked)
    account = Keyword.get(choice, :budget_account_id, current)

    with :ok <- check_account(scope, account, current) do
      written = %{scope: scope, link: link, id: expense_id, old: old, account: current}
      write_wanted(written, linked, wanted(new, link, account), choice[:adopt])
    end
  end

  defp write_wanted(_written, nil, nil, _adopt), do: :ok

  defp write_wanted(written, nil, wanted, %Transaction{} = adopt),
    do: adopt(written.scope, written.id, adopt, wanted)

  defp write_wanted(written, nil, wanted, nil) do
    if is_nil(written.old) or started?(written.link, wanted.date),
      do: create(written.scope, written.link, written.id, wanted),
      else: :ok
  end

  defp write_wanted(written, linked, nil, _adopt), do: remove(written.scope, written.id, linked)

  defp write_wanted(written, linked, wanted, _adopt) do
    old = wanted(written.old, written.link, written.account)
    change(written.scope, written.id, linked, old, wanted)
  end

  defp started?(%Link{start_date: nil}, _date), do: true
  defp started?(%Link{start_date: start}, date), do: not Date.before?(date, start)

  defp linked_transaction(scope, expense_id) do
    Repo.one(
      from t in Transaction,
        where:
          t.user_id == ^scope.user.id and t.kasse_expense_id == ^expense_id and
            is_nil(t.deleted_at)
    )
  end

  defp transfer_account_id(%Transaction{payee_id: nil}), do: nil

  defp transfer_account_id(%Transaction{payee_id: payee_id}),
    do: Repo.one(from p in Payee, where: p.id == ^payee_id, select: p.transfer_account_id)

  defp check_account(scope, account_id, current) do
    if is_nil(account_id) or account_id == current or
         Enum.any?(reimbursement_accounts_of(scope.user.id), &(&1.id == account_id)),
       do: :ok,
       else: {:error, "Das Konto für die Rückzahlung gibt es im Budget nicht."}
  end

  defp wanted(nil, _link, _account_id), do: nil

  defp wanted(%Expense{} = expense, link, account_id) do
    change = Kasse.Ledger.change(expense, link.participant_id)

    if not Expense.deleted?(expense) and change != 0 do
      %{
        amount: change,
        date: expense.date,
        payee: payee(expense, account_id),
        kasse_category_id: if(!expense.reimbursement, do: expense.category_id),
        memo: memo(expense)
      }
    end
  end

  defp payee(%Expense{reimbursement: true}, account_id) when not is_nil(account_id),
    do: {:account, account_id}

  defp payee(expense, _account_id), do: {:name, expense.title}

  defp payee_attrs({:name, name}), do: %{payee_name: name}

  defp payee_attrs({:account, account_id}),
    do: %{
      payee_id:
        Repo.one!(from p in Payee, where: p.transfer_account_id == ^account_id, select: p.id),
      category_id: nil
    }

  @doc ~S|The memo of a linked transaction: "Gesamt 12,34 € (… USD) · bezahlt von X".|
  def memo(%Expense{} = expense) do
    total = "Gesamt " <> Money.plain(expense.amount_cents)

    total =
      if Expense.foreign?(expense),
        do: total <> " (#{Money.plain(expense.original_amount, expense.original_currency)})",
        else: total

    total <> " · bezahlt von " <> expense.paid_by.name
  end

  defp create(scope, link, expense_id, wanted) do
    attrs =
      Map.merge(payee_attrs(wanted.payee), %{
        account_id: link.account_id,
        date: wanted.date,
        amount: wanted.amount,
        category_id: budget_category_id(wanted.kasse_category_id),
        memo: wanted.memo,
        cleared: :cleared,
        source: :kasse
      })

    with {:ok, _transaction} <-
           Ledger.create_transaction(scope, attrs, led_by: {:kasse_expense, expense_id}) do
      :ok
    end
  end

  # The transaction keeps what the register gave it but for what the expense leads.
  defp adopt(scope, expense_id, transaction, wanted) do
    with {:ok, transaction} <- Ledger.lead(scope, transaction, {:kasse_expense, expense_id}) do
      attrs =
        Map.reject(%{amount: wanted.amount, date: wanted.date}, fn {field, value} ->
          Map.fetch!(transaction, field) == value
        end)

      if attrs == %{}, do: :ok, else: rewrite(scope, expense_id, transaction, attrs)
    end
  end

  defp remove(scope, expense_id, transaction) do
    with :ok <- check_unreconciled(transaction),
         {:ok, _deleted} <-
           Ledger.delete_transaction(scope, transaction, led_by: {:kasse_expense, expense_id}) do
      :ok
    end
  end

  defp change(scope, expense_id, transaction, old, new) do
    changed? = &(is_nil(old) or Map.fetch!(old, &1) != Map.fetch!(new, &1))
    written_memo? = is_nil(old) or transaction.memo == old.memo

    attrs =
      [
        {changed?.(:amount), %{amount: new.amount}},
        {changed?.(:date), %{date: new.date}},
        {changed?.(:payee), payee_attrs(new.payee)},
        {changed?.(:kasse_category_id),
         %{category_id: budget_category_id(new.kasse_category_id)}},
        {changed?.(:memo) and written_memo?, %{memo: new.memo}}
      ]
      |> Enum.filter(&elem(&1, 0))
      |> Enum.reduce(%{}, &Map.merge(&2, elem(&1, 1)))

    if attrs == %{}, do: :ok, else: rewrite(scope, expense_id, transaction, attrs)
  end

  defp rewrite(scope, expense_id, transaction, attrs) do
    with :ok <- check_unreconciled(transaction),
         {:ok, _transaction} <-
           Ledger.update_transaction(scope, transaction, attrs,
             led_by: {:kasse_expense, expense_id}
           ) do
      :ok
    end
  end

  defp check_unreconciled(transaction) do
    ids = Enum.reject([transaction.id, transaction.transfer_transaction_id], &is_nil/1)

    reconciled_in =
      Repo.one(
        from t in Transaction,
          join: a in assoc(t, :account),
          where: t.id in ^ids and t.cleared == :reconciled,
          select: a.name,
          limit: 1
      )

    subject = if transaction.transfer_transaction_id, do: "Die Rückzahlung", else: "Die Ausgabe"

    if reconciled_in,
      do:
        {:error,
         "#{subject} ist im Budget im Konto „#{reconciled_in}“ abgeglichen und muss zuerst dort geändert werden."},
      else: :ok
  end

  @doc """
  Writes a transaction of the register through the Ledger, `original` changed or a new one (nil), with `opts` for
  the Ledger. When the write makes it a transfer between the shared-expenses account and a budget account,
  dated from the link's start date on, the scope's user's linked person gets a reimbursement in the same database
  transaction, which leads the transfer from then on: it completes an open one without account of the same amount,
  dated within the match window (`Abakus.Ledger.Matches.days/0`), or is a new one with `:person_id`, which may be left
  out while the group has only one other active person (`reimbursement_people/1`). A write that makes it such a
  transfer in a split's part or with an account that is no open budget account is refused. Returns what the Ledger
  does, or `{:error, message}` in German.
  """
  def write_from_register(%Scope{} = scope, original, attrs, opts \\ []) do
    Repo.transact(fn ->
      link = user_link(scope)
      before = original && link && shared_transfer(link, own_transaction(scope, original.id))

      with {:ok, transaction} <- ledger_write(scope, original, attrs, opts),
           :ok <- reimburse(link, before, transaction, opts[:person_id]) do
        {:ok, transaction}
      end
    end)
  end

  @doc """
  For the register: the shared-expenses account of the scope's user, the link's start date and the other active
  people of the group a reimbursement can be with, by name; nil while the user is not linked.
  """
  def reimbursement_people(%Scope{} = scope) do
    if link = user_link(scope),
      do: %{account_id: link.account_id, start_date: link.start_date, people: others(link)}
  end

  defp user_link(%Scope{user: %User{id: user_id}}) do
    Repo.one(
      from l in Link,
        join: a in assoc(l, :account),
        where: a.user_id == ^user_id,
        preload: [:account, :participant]
    )
  end

  defp user_link(_scope), do: nil

  defp others(link) do
    Repo.all(
      from p in Participant,
        where: is_nil(p.archived_at) and p.id != ^link.participant_id,
        order_by: [fragment("? COLLATE NOCASE", p.name), p.id]
    )
  end

  defp own_transaction(scope, id), do: Repo.get_by!(Transaction, id: id, user_id: scope.user.id)

  defp ledger_write(scope, nil, attrs, opts),
    do: Ledger.create_transaction(scope, attrs, Keyword.take(opts, [:reconciled]))

  defp ledger_write(scope, original, attrs, opts),
    do: Ledger.update_transaction(scope, original, attrs, Keyword.take(opts, [:reconciled]))

  defp reimburse(nil = _link, _before, _transaction, _person_id), do: :ok

  defp reimburse(link, nil, transaction, person_id) do
    case shared_transfer(link, transaction) do
      nil ->
        :ok

      :unreimbursable ->
        {:error,
         "Eine Umbuchung mit „#{link.account.name}“ wird eine Rückzahlung in der Kasse und geht deshalb nur als " <>
           "ganze Buchung mit einem offenen Budget-Konto."}

      {_side, _other} when not is_nil(link.participant.archived_at) ->
        {:error,
         "Deine Person in der Kasse ist archiviert, deshalb kann eine Umbuchung mit „#{link.account.name}“ " <>
           "keine Rückzahlung werden."}

      {side, other} ->
        complete_or_create(link, side, other.account_id, person_id)
    end
  end

  defp reimburse(_link, _before, _transaction, _person_id), do: :ok

  defp shared_transfer(link, transaction) do
    transaction =
      Repo.preload(transaction, [:transfer_transaction, subtransactions: :transfer_transaction],
        force: true
      )

    counterpart = transaction.transfer_transaction

    cond do
      not unled_since_start?(link, transaction, counterpart) ->
        nil

      split_part_with?(link, transaction) ->
        :unreimbursable

      pair = counterpart && link_side(link, transaction, counterpart) ->
        reimbursable(pair)

      true ->
        nil
    end
  end

  defp unled_since_start?(link, transaction, counterpart) do
    is_nil(transaction.deleted_at) and is_nil(Transaction.led_by(transaction)) and
      is_nil(counterpart && Transaction.led_by(counterpart)) and started?(link, transaction.date)
  end

  defp split_part_with?(%Link{account_id: id}, transaction) do
    (transaction.account_id == id and not is_nil(transaction.transfer_subtransaction_id)) or
      Enum.any?(
        transaction.subtransactions,
        &match?(%Subtransaction{transfer_transaction: %Transaction{account_id: ^id}}, &1)
      )
  end

  defp reimbursable({side, other}) do
    if Enum.any?(reimbursement_accounts_of(side.user_id), &(&1.id == other.account_id)),
      do: {side, other},
      else: :unreimbursable
  end

  defp link_side(%Link{account_id: id}, %Transaction{account_id: id} = side, other),
    do: {side, other}

  defp link_side(%Link{account_id: id}, other, %Transaction{account_id: id} = side),
    do: {side, other}

  defp link_side(_link, _transaction, _counterpart), do: nil

  defp complete_or_create(link, side, account_id, person_id) do
    scope = Scope.for_participant(link.participant)

    case open_reimbursement(scope, link, side, person_id) do
      {open, expense} ->
        complete(scope, link, open, expense, side, account_id)

      nil ->
        with {:ok, person_id} <- other_person(link, person_id) do
          create_reimbursement(scope, link, side, account_id, person_id)
        end
    end
  end

  defp open_reimbursement(scope, link, side, person_id) do
    scope
    |> open_reimbursements(link, side)
    |> Enum.filter(fn {_open, expense} -> is_nil(person_id) or involves?(expense, person_id) end)
    |> Enum.min_by(
      fn {open, _expense} ->
        {abs(Date.diff(open.date, side.date)), Date.to_gregorian_days(open.date), open.id}
      end,
      fn -> nil end
    )
  end

  defp open_reimbursements(scope, link, side) do
    days = Matches.days()

    from(t in Transaction,
      join: e in Expense,
      on: e.id == t.kasse_expense_id,
      where:
        t.user_id == ^scope.user.id and t.account_id == ^link.account_id and
          is_nil(t.deleted_at) and is_nil(t.transfer_transaction_id) and e.reimbursement and
          is_nil(e.deleted_at) and t.amount == ^side.amount and
          t.date >= ^Date.add(side.date, -days) and t.date <= ^Date.add(side.date, days),
      select: {t, e}
    )
    |> Repo.all()
    |> Enum.map(fn {open, expense} -> {open, Repo.preload(expense, [:paid_by, :shares])} end)
  end

  defp involves?(expense, person_id),
    do: expense.paid_by_id == person_id or Expense.share_of(expense, person_id) != 0

  defp complete(scope, link, open, expense, side, account_id) do
    with :ok <- remove(scope, expense.id, open) do
      adopt(scope, expense.id, side, wanted(expense, link, account_id))
    end
  end

  defp other_person(link, nil) do
    case others(link) do
      [person] -> {:ok, person.id}
      [] -> {:error, "In der Kasse gibt es niemanden, mit dem das eine Rückzahlung wäre."}
      _several -> {:error, "Bitte wählen, mit wem in der Kasse die Rückzahlung ist."}
    end
  end

  defp other_person(link, person_id) do
    if Enum.any?(others(link), &(&1.id == person_id)),
      do: {:ok, person_id},
      else: {:error, "Diese Person gibt es in der Kasse nicht."}
  end

  defp create_reimbursement(scope, link, side, account_id, person_id) do
    {payer, recipient} =
      if side.amount > 0,
        do: {link.participant_id, person_id},
        else: {person_id, link.participant_id}

    attrs = %{
      title: Expense.reimbursement_title(),
      date: side.date,
      paid_by_id: payer,
      amount_cents: abs(side.amount),
      reimbursement: true,
      parts: [%{participant_id: recipient, weight: 0}]
    }

    case Expenses.create_expense(scope, attrs,
           text: "Aus einer Umbuchung im Budget angelegt",
           budget_account_id: account_id,
           adopt: side
         ) do
      {:ok, _expense} -> :ok
      {:error, %Changeset{} = changeset} -> {:error, expense_errors(changeset)}
    end
  end

  defp expense_errors(changeset),
    do: Enum.map_join(changeset.errors, " ", fn {_field, {message, _opts}} -> message end)

  defp budget_category_id(nil), do: nil

  defp budget_category_id(kasse_category_id) do
    Repo.one(
      from m in CategoryMapping,
        where: m.category_id == ^kasse_category_id,
        select: m.budget_category_id
    )
  end

  defp refused(changeset) do
    errors =
      changeset
      |> Changeset.traverse_errors(fn {message, _opts} -> message end)
      |> Enum.flat_map(fn {field, messages} -> Enum.map(messages, &"#{field} #{&1}") end)
      |> Enum.join(", ")

    "Die Buchung im Budget ließ sich nicht schreiben (#{errors})."
  end

  @doc "The budget category each Kasse category is mapped to, by Kasse category id; unmapped ones are missing."
  def category_mapping(%Scope{} = scope) do
    owner!(scope)
    mapping()
  end

  defp mapping do
    Repo.all(from m in CategoryMapping, select: {m.category_id, m.budget_category_id})
    |> Map.new()
  end

  @doc """
  Maps Kasse categories to budget categories: budget category ids (nil or `""` for none) by Kasse category id,
  also as text; Kasse categories left out keep theirs. Only regular budget categories can be chosen.
  """
  def put_category_mapping(%Scope{} = scope, mapping) do
    owner!(scope)

    with {:ok, mapping} <- cast_mapping(mapping) do
      Repo.transact(fn -> replace_mapping(scope, mapping) end)
    end
  end

  defp replace_mapping(scope, mapping) do
    with :ok <- check_mapping(scope, mapping) do
      Repo.delete_all(from m in CategoryMapping, where: m.category_id in ^Map.keys(mapping))

      Repo.insert_all(
        CategoryMapping,
        for(
          {id, budget_id} <- mapping,
          budget_id,
          do: %{category_id: id, budget_category_id: budget_id}
        )
      )

      {:ok, mapping()}
    end
  end

  defp check_mapping(scope, mapping) do
    known = Repo.all(from c in Category, select: c.id)
    chosen = mapping |> Map.values() |> Enum.reject(&is_nil/1) |> Enum.uniq()

    regular =
      Repo.all(
        from c in BudgetCategory,
          where: c.user_id == ^scope.user.id and c.id in ^chosen and not c.internal,
          select: c.id
      )

    cond do
      Enum.any?(Map.keys(mapping), &(&1 not in known)) ->
        {:error, "Unbekannte Kategorie der Kasse."}

      length(regular) < length(chosen) ->
        {:error, "Unbekannte Kategorie im Budget. Bitte die Seite neu laden."}

      true ->
        :ok
    end
  end

  defp cast_mapping(mapping) do
    Enum.reduce_while(mapping, {:ok, %{}}, fn {id, budget_id}, {:ok, cast} ->
      with {:ok, id} <- Abakus.Schema.cast_id(id),
           {:ok, budget_id} <- cast_budget_id(budget_id) do
        {:cont, {:ok, Map.put(cast, id, budget_id)}}
      else
        :error -> {:halt, {:error, "Unbekannte Kategorie."}}
      end
    end)
  end

  defp cast_budget_id(blank) when blank in [nil, ""], do: {:ok, nil}
  defp cast_budget_id(id), do: Abakus.Ids.cast(id)

  @doc "Moves the mapping from one of the user's budget categories to another, as deleting `from_id` does."
  def recategorize(%Scope{user: %User{id: user_id}}, from_id, to_id) do
    categories = from c in BudgetCategory, where: c.user_id == ^user_id, select: c.id

    Repo.update_all(
      from(m in CategoryMapping,
        where: m.budget_category_id == ^from_id and m.budget_category_id in subquery(categories)
      ),
      set: [budget_category_id: to_id]
    )

    :ok
  end

  @doc "The transaction an expense is linked to, with its category and payee, for the budget owner; nil for none."
  def transaction_for(%Scope{} = scope, expense_id) do
    Access.check!(scope)
    if Scope.budget_owner?(scope), do: linked_to(scope, expense_id)
  end

  defp linked_to(scope, expense_id),
    do:
      scope
      |> linked_transaction(expense_id)
      |> Repo.preload([:category, payee: :transfer_account])

  defp owner!(scope) do
    Access.check!(scope)
    if !Scope.budget_owner?(scope), do: raise(AccessError)
  end
end
