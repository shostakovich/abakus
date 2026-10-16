defmodule Abakus.Kasse.BudgetLink do
  @moduledoc """
  Expenses linked to the budget (ADR 0006). A linked participant (the budget owner, once switched on) has their
  share of every expense as a transaction in the account fed by `shared_expenses`, written through the Ledger in
  the expense's database transaction: minus the share, dated as the expense, the title as payee, the budget category
  the Kasse category is mapped to, a memo describing the expense, created cleared and unapproved. Reimbursements and
  expenses without a share of theirs give none. An expense dated before the link's start date gets none unless its
  marked transaction was adopted, it is entered after the switch or it is moved to a later date.

  The Kasse leads on what it changes: amount, date and payee follow every change of the expense. The register may
  change category, memo, flag, cleared state and approval; a later Kasse change keeps a category or memo the
  register changed, but a change of the Kasse category always writes the mapped category.

  The functions the link's page calls take the caller's scope; only the budget owner's may switch it on, choose the
  account or map the categories. The link's tables stay out of the MCP's SQL sandbox, as they point into the budget.
  """

  import Ecto.Query

  alias Abakus.Categories.Category, as: BudgetCategory
  alias Abakus.Kasse.{Access, AccessError}
  alias Abakus.Kasse.BudgetLink.{CategoryMapping, Link, LinkedTransaction}
  alias Abakus.Kasse.Categories.Category
  alias Abakus.Kasse.Expenses.Expense
  alias Abakus.Kasse.Ynab.{Connections, Posting, Scheduler}
  alias Abakus.Ledger
  alias Abakus.Ledger.{Account, Transaction}
  alias Abakus.Money
  alias Abakus.Repo
  alias Abakus.Users.Scope
  alias Ecto.Changeset

  @register_fields [:category_id, :memo, :flag, :cleared, :approved]

  @doc "The fields of a linked transaction the register may change."
  def register_fields, do: @register_fields

  @doc "The accounts a participant can be linked to: open budget accounts not fed by another app, in order."
  def account_choices(%Scope{} = scope) do
    owner!(scope)
    choices()
  end

  defp choices do
    Repo.all(
      from a in Account,
        where:
          a.kind in ^Account.budget_kinds() and not a.closed and
            (is_nil(a.fed_by) or a.fed_by == :shared_expenses),
        order_by: [a.position, a.id]
    )
  end

  @doc """
  Links the scope's person, the budget owner's participant, to the budget, in one step after the final YNAB import:
  the account `account_id` (one of `account_choices/1`) becomes the one fed by shared expenses; its transactions
  whose memo ends with the YNAB sync's marker become their expenses' linked transactions, whatever their date; every
  expense since the start date of the participant's YNAB connection without one gets one; and the YNAB connection is
  removed.
  Returns `{:ok, %{adopted:, created:, unadoptable:, left:}}`, `unadoptable` the marked transactions of an expense
  that could not be adopted (a split, a transfer or a second one for the expense), `left` those without an expense
  that wants a booking; or `{:error, reason}`: `:not_budget_owner`, `:linked`, `:no_account` or a message in German.
  """
  def switch_on(%Scope{} = scope, account_id) do
    participant = Access.person!(scope)

    Scheduler.change_connection(fn ->
      Repo.transact(fn -> link(scope, participant, account_id) end)
    end)
  end

  defp link(scope, participant, account_id) do
    with :ok <- check_linkable(scope, participant),
         {:ok, account} <- feed(account_id),
         {:ok, connection} <- Connections.remove(participant.id) do
      %Link{
        participant_id: participant.id,
        account_id: account.id,
        start_date: connection && connection.start_date
      }
      |> Repo.insert!()
      |> take_over()
    end
  end

  defp check_linkable(scope, participant) do
    cond do
      not Scope.budget_owner?(scope) -> {:error, :not_budget_owner}
      Repo.exists?(where(Link, participant_id: ^participant.id)) -> {:error, :linked}
      true -> :ok
    end
  end

  defp feed(account_id) do
    with {:ok, id} <- Abakus.Schema.cast_id(account_id),
         %Account{} = account <- Enum.find(choices(), &(&1.id == id)) do
      Repo.update_all(
        from(a in Account, where: a.fed_by == :shared_expenses and a.id != ^id),
        set: [fed_by: nil]
      )

      Ledger.update_account(account, %{fed_by: :shared_expenses})
    else
      _none -> {:error, :no_account}
    end
  end

  defp take_over(link) do
    marked = marked_transactions(link)
    by_expense = Enum.group_by(marked, &Posting.marker_id(&1.memo))
    none = %{adopted: 0, created: 0, unadoptable: 0}

    link.start_date
    |> expenses_to_take_over(Map.keys(by_expense))
    |> Enum.reduce_while({:ok, none}, fn expense, {:ok, counts} ->
      case take_over_expense(link, expense, Map.get(by_expense, expense.id, [])) do
        {:ok, done} -> {:cont, {:ok, Map.merge(counts, done, fn _key, a, b -> a + b end)}}
        {:error, %Changeset{} = changeset} -> {:halt, {:error, refused(changeset)}}
      end
    end)
    |> case do
      {:ok, counts} ->
        {:ok, Map.put(counts, :left, length(marked) - counts.adopted - counts.unadoptable)}

      error ->
        error
    end
  end

  # The first plain marked transaction is adopted; the others are left to the owner, and so is an expense whose
  # marked transactions are all splits or transfers, rather than booking its share twice.
  defp take_over_expense(link, expense, marked) do
    wanted = if !linked_transaction(expense.id, link.participant_id), do: wanted(expense, link)

    case {wanted, Enum.find(marked, &plain?/1)} do
      {nil, _plain} ->
        {:ok, %{}}

      {wanted, nil} when marked == [] ->
        with :ok <- create(link, expense.id, wanted), do: {:ok, %{created: 1}}

      {_wanted, nil} ->
        {:ok, %{unadoptable: length(marked)}}

      {wanted, plain} ->
        with :ok <- adopt(link, expense.id, plain, wanted),
             do: {:ok, %{adopted: 1, unadoptable: length(marked) - 1}}
    end
  end

  # The marked transactions in the account, whatever their date, the first for each expense first.
  defp marked_transactions(link) do
    from(t in Transaction,
      where:
        t.account_id == ^link.account_id and is_nil(t.deleted_at) and
          is_nil(t.matched_transaction_id) and like(t.memo, "%zipfelkasse #%"),
      order_by: t.id,
      preload: :subtransactions
    )
    |> Repo.all()
    |> Enum.filter(&Posting.marker_id(&1.memo))
  end

  # A split or a transfer cannot follow the expense's amount and category.
  defp plain?(transaction),
    do: transaction.subtransactions == [] and is_nil(transaction.transfer_transaction_id)

  # The expenses since the start date, and older ones with a marked transaction.
  defp expenses_to_take_over(start_date, marked_ids) do
    ids = for id <- marked_ids, {:ok, id} <- [Abakus.Schema.cast_id(id)], do: id

    from(e in Expense,
      where: is_nil(e.deleted_at) and not e.reimbursement,
      order_by: [e.date, e.id],
      preload: [:paid_by, :shares]
    )
    |> since_or_marked(start_date, ids)
    |> Repo.all()
  end

  defp since_or_marked(query, nil, _ids), do: query
  defp since_or_marked(query, date, ids), do: where(query, [e], e.date >= ^date or e.id in ^ids)

  # The transaction keeps its category, cleared state, approval and flag; the rest follows the expense.
  defp adopt(link, expense_id, transaction, wanted) do
    attrs = %{
      amount: wanted.amount,
      date: wanted.date,
      payee_name: wanted.payee,
      memo: wanted.memo
    }

    with {:ok, transaction} <-
           Ledger.update_transaction(transaction, attrs, reconciled: :confirmed) do
      insert_linked(link, expense_id, transaction)
    end
  end

  @doc "The account the scope's person's shares are booked in; nil while they are not linked."
  def account(%Scope{} = scope) do
    id = Access.person!(scope).id

    Repo.one(
      from l in Link, join: a in assoc(l, :account), where: l.participant_id == ^id, select: a
    )
  end

  @doc "From when switching on books the scope's person's shares: the start date of their YNAB connection, or nil."
  def start_date(%Scope{} = scope) do
    connection = Connections.get(Access.person!(scope).id)
    connection && connection.start_date
  end

  @doc "Whether anything is linked or mapped, which a wipe of the budget would break or drop."
  def in_use?,
    do: Repo.exists?(Link) or Repo.exists?(LinkedTransaction) or Repo.exists?(CategoryMapping)

  @doc """
  Writes what a change of an expense means for the linked transactions, inside the caller's database transaction:
  `old` and `new` are the expense before and after (nil for none, both with payer and shares). Returns `:ok` or
  `{:error, message}`, in German.
  """
  def expense_written(old, new) do
    Enum.reduce_while(Repo.all(from l in Link, order_by: l.participant_id), :ok, fn link, :ok ->
      case write(link, old, new) do
        :ok -> {:cont, :ok}
        {:error, %Changeset{} = changeset} -> {:halt, {:error, refused(changeset)}}
      end
    end)
  end

  defp write(link, old, new) do
    expense_id = (new || old).id

    case {linked_transaction(expense_id, link.participant_id), wanted(new, link)} do
      {nil, nil} ->
        :ok

      {nil, wanted} ->
        if is_nil(old) or started?(link, wanted), do: create(link, expense_id, wanted), else: :ok

      {linked, nil} ->
        remove(linked)

      {linked, wanted} ->
        change(linked, wanted(old, link), wanted)
    end
  end

  defp started?(%Link{start_date: nil}, _wanted), do: true
  defp started?(%Link{start_date: start}, wanted), do: not Date.before?(wanted.date, start)

  # A transaction deleted beside the Kasse is booked anew.
  defp linked_transaction(expense_id, participant_id) do
    case Repo.get_by(LinkedTransaction, expense_id: expense_id, participant_id: participant_id) do
      nil ->
        nil

      linked ->
        linked = Repo.preload(linked, :transaction)

        if linked.transaction.deleted_at do
          Repo.delete!(linked)
          nil
        else
          linked
        end
    end
  end

  defp wanted(nil, _link), do: nil

  defp wanted(%Expense{} = expense, link) do
    share = Expense.share_of(expense, link.participant_id)

    if not Expense.deleted?(expense) and not expense.reimbursement and share > 0 do
      %{
        amount: -share,
        date: expense.date,
        payee: expense.title,
        kasse_category_id: expense.category_id,
        memo: memo(expense)
      }
    end
  end

  @doc ~S|The memo of a linked transaction: "Gesamt 12,34 € (… USD) · bezahlt von X".|
  def memo(%Expense{} = expense) do
    total = "Gesamt " <> Money.plain(expense.amount_cents)

    total =
      if Expense.foreign?(expense),
        do: total <> " (#{Money.plain(expense.original_amount, expense.original_currency)})",
        else: total

    total <> " · bezahlt von " <> expense.paid_by.name
  end

  defp create(link, expense_id, wanted) do
    attrs = %{
      account_id: link.account_id,
      date: wanted.date,
      amount: wanted.amount,
      payee_name: wanted.payee,
      category_id: budget_category_id(wanted.kasse_category_id),
      memo: wanted.memo,
      cleared: :cleared,
      source: :kasse
    }

    with {:ok, transaction} <- Ledger.create_transaction(attrs) do
      insert_linked(link, expense_id, transaction)
    end
  end

  defp insert_linked(link, expense_id, transaction) do
    Repo.insert!(%LinkedTransaction{
      expense_id: expense_id,
      participant_id: link.participant_id,
      transaction_id: transaction.id,
      written_category_id: transaction.category_id,
      written_memo: transaction.memo
    })

    :ok
  end

  defp remove(linked) do
    with {:ok, _deleted} <- Ledger.delete_transaction(linked.transaction, reconciled: :confirmed) do
      Repo.delete!(linked)
      :ok
    end
  end

  defp change(linked, old, new) do
    transaction = linked.transaction
    changed? = &(is_nil(old) or Map.fetch!(old, &1) != Map.fetch!(new, &1))

    attrs =
      [
        {changed?.(:amount), :amount, new.amount},
        {changed?.(:date), :date, new.date},
        {changed?.(:payee), :payee_name, new.payee},
        {changed?.(:kasse_category_id), :category_id, budget_category_id(new.kasse_category_id)},
        {changed?.(:memo) and transaction.memo == linked.written_memo, :memo, new.memo}
      ]
      |> Enum.filter(&elem(&1, 0))
      |> Map.new(fn {true, field, value} -> {field, value} end)

    if attrs == %{}, do: :ok, else: rewrite(linked, attrs)
  end

  defp rewrite(linked, attrs) do
    with {:ok, transaction} <-
           Ledger.update_transaction(linked.transaction, attrs, reconciled: :confirmed) do
      written =
        for {field, written} <- [category_id: :written_category_id, memo: :written_memo],
            Map.has_key?(attrs, field),
            do: {written, Map.fetch!(transaction, field)}

      linked |> Changeset.change(written) |> Repo.update!(force: true)
      :ok
    end
  end

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
      Repo.transact(fn -> replace_mapping(mapping) end)
    end
  end

  defp replace_mapping(mapping) do
    with :ok <- check_mapping(mapping) do
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

  defp check_mapping(mapping) do
    known = Repo.all(from c in Category, select: c.id)
    chosen = mapping |> Map.values() |> Enum.reject(&is_nil/1) |> Enum.uniq()

    regular =
      Repo.all(from c in BudgetCategory, where: c.id in ^chosen and not c.internal, select: c.id)

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
      with {:ok, id} <- cast_id(id),
           {:ok, budget_id} <- cast_optional_id(budget_id) do
        {:cont, {:ok, Map.put(cast, id, budget_id)}}
      else
        :error -> {:halt, {:error, "Unbekannte Kategorie."}}
      end
    end)
  end

  defp cast_optional_id(blank) when blank in [nil, ""], do: {:ok, nil}
  defp cast_optional_id(id), do: cast_id(id)

  defp cast_id(id), do: Abakus.Schema.cast_id(id)

  @doc "Moves the mapping and what the Kasse wrote from one budget category to another, as deleting `from_id` does."
  def recategorize(from_id, to_id) do
    Repo.update_all(where(CategoryMapping, budget_category_id: ^from_id),
      set: [budget_category_id: to_id]
    )

    Repo.update_all(where(LinkedTransaction, written_category_id: ^from_id),
      set: [written_category_id: to_id]
    )

    :ok
  end

  @doc "The expense id of each linked transaction among `transaction_ids`, by transaction id."
  def expense_ids(transaction_ids) do
    Repo.all(
      from l in LinkedTransaction,
        where: l.transaction_id in ^transaction_ids,
        select: {l.transaction_id, l.expense_id}
    )
    |> Map.new()
  end

  @doc "The transaction an expense is linked to, with its category, for the budget owner; nil for none."
  def transaction_for(%Scope{} = scope, expense_id) do
    Access.check!(scope)
    if Scope.budget_owner?(scope), do: linked_to(expense_id)
  end

  defp linked_to(expense_id) do
    Repo.one(
      from t in Transaction,
        join: l in LinkedTransaction,
        on: l.transaction_id == t.id,
        where: l.expense_id == ^expense_id and is_nil(t.deleted_at),
        order_by: l.participant_id,
        limit: 1,
        preload: :category
    )
  end

  defp owner!(scope) do
    Access.check!(scope)
    if !Scope.budget_owner?(scope), do: raise(AccessError)
  end
end
