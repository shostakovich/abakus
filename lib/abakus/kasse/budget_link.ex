defmodule Abakus.Kasse.BudgetLink do
  @moduledoc """
  Expenses linked to the budget (ADR 0020). A linked participant (the budget owner, once switched on) has what each
  expense changes in their Kasse balance, paid minus share, as a transaction in the account fed by
  `shared_expenses`, so its balance is their Kasse balance. It is written through the Ledger with their scope in the
  expense's database transaction: dated as the expense, the title as payee, the budget category the Kasse category
  is mapped to, a memo describing the expense, created cleared and unapproved. Their bank purchase of an expense
  they paid stays a purchase in its category, which so bears only their share. Reimbursements and expenses that
  change nothing for them give none. An expense dated before the link's start date, if it has one, gets none
  unless it is entered after the switch or moved to a later date.

  The transaction refers to its expense, which leads it: amount, date and payee follow every change of the expense,
  and the Ledger refuses them to anyone else. Category, memo, cleared state and approval are the register's; a later
  Kasse change keeps a memo the register changed, but a change of the Kasse category always writes the mapped
  category.

  The functions the link's page calls take the caller's scope; only the budget owner's may switch it on, choose the
  account or map the categories. Those the budget calls take its user's scope and see only what points into their
  budget. The link's tables stay out of the MCP's SQL sandbox, as they point into the budget.
  """

  import Ecto.Query

  alias Abakus.Categories.Category, as: BudgetCategory
  alias Abakus.Kasse
  alias Abakus.Kasse.{Access, AccessError}
  alias Abakus.Kasse.BudgetLink.{CategoryMapping, Link}
  alias Abakus.Kasse.Categories.Category
  alias Abakus.Kasse.Expenses.Expense
  alias Abakus.Ledger
  alias Abakus.Ledger.{Account, Transaction}
  alias Abakus.Money
  alias Abakus.Repo
  alias Abakus.Users.{Scope, User}
  alias Ecto.Changeset

  @doc "The accounts a participant can be linked to: open budget accounts not fed by another app, in order."
  def account_choices(%Scope{} = scope) do
    owner!(scope)
    choices(scope)
  end

  defp choices(scope) do
    Repo.all(
      from a in Account,
        where:
          a.user_id == ^scope.user.id and a.kind in ^Account.budget_kinds() and not a.closed and
            (is_nil(a.fed_by) or a.fed_by == :shared_expenses),
        order_by: [a.position, a.id]
    )
  end

  @doc """
  Links the scope's person, the budget owner's participant, to the budget: the account `account_id` (one of
  `account_choices/1`) becomes the one fed by shared expenses, and every expense that changes their balance gets
  its transaction. Returns `{:ok, %{created: count}}` or `{:error, reason}`: `:not_budget_owner`, `:linked`,
  `:no_account` or a message in German.
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
    with {:ok, id} <- Abakus.Schema.cast_id(account_id),
         %Account{} = account <- Enum.find(choices(scope), &(&1.id == id)) do
      Repo.update_all(
        from(a in Account,
          where: a.user_id == ^scope.user.id and a.fed_by == :shared_expenses and a.id != ^id
        ),
        set: [fed_by: nil]
      )

      Ledger.update_account(scope, account, %{fed_by: :shared_expenses})
    else
      _none -> {:error, :no_account}
    end
  end

  defp book_all(link, scope) do
    from(e in Expense,
      where: is_nil(e.deleted_at) and not e.reimbursement,
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
    case wanted(expense, link) do
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
  `old` and `new` are the expense before and after (nil for none, both with payer and shares). Returns `:ok` or
  `{:error, message}`, in German.
  """
  def expense_written(old, new) do
    links = Repo.all(from l in Link, order_by: l.participant_id, preload: :participant)

    Enum.reduce_while(links, :ok, fn link, :ok ->
      case write(Scope.for_participant(link.participant), link, old, new) do
        :ok -> {:cont, :ok}
        {:error, %Changeset{} = changeset} -> {:halt, {:error, refused(changeset)}}
      end
    end)
  end

  defp write(scope, link, old, new) do
    expense_id = (new || old).id

    case {linked_transaction(scope, expense_id), wanted(new, link)} do
      {nil, nil} ->
        :ok

      {nil, wanted} ->
        if is_nil(old) or started?(link, wanted),
          do: create(scope, link, expense_id, wanted),
          else: :ok

      {linked, nil} ->
        remove(scope, expense_id, linked)

      {linked, wanted} ->
        change(scope, expense_id, linked, wanted(old, link), wanted)
    end
  end

  defp started?(%Link{start_date: nil}, _wanted), do: true
  defp started?(%Link{start_date: start}, wanted), do: not Date.before?(wanted.date, start)

  defp linked_transaction(scope, expense_id) do
    Repo.one(
      from t in Transaction,
        where:
          t.user_id == ^scope.user.id and t.kasse_expense_id == ^expense_id and
            is_nil(t.deleted_at)
    )
  end

  defp wanted(nil, _link), do: nil

  defp wanted(%Expense{} = expense, link) do
    change = Kasse.Ledger.change(expense, link.participant_id)

    if not Expense.deleted?(expense) and not expense.reimbursement and change != 0 do
      %{
        amount: change,
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

  defp create(scope, link, expense_id, wanted) do
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

    with {:ok, _transaction} <-
           Ledger.create_transaction(scope, attrs, led_by: {:kasse_expense, expense_id}) do
      :ok
    end
  end

  defp remove(scope, expense_id, transaction) do
    with {:ok, _deleted} <- Ledger.delete_transaction(scope, transaction, opts(expense_id)) do
      :ok
    end
  end

  defp opts(expense_id), do: [reconciled: :confirmed, led_by: {:kasse_expense, expense_id}]

  defp change(scope, expense_id, transaction, old, new) do
    changed? = &(is_nil(old) or Map.fetch!(old, &1) != Map.fetch!(new, &1))
    written_memo? = is_nil(old) or transaction.memo == old.memo

    attrs =
      [
        {changed?.(:amount), :amount, new.amount},
        {changed?.(:date), :date, new.date},
        {changed?.(:payee), :payee_name, new.payee},
        {changed?.(:kasse_category_id), :category_id, budget_category_id(new.kasse_category_id)},
        {changed?.(:memo) and written_memo?, :memo, new.memo}
      ]
      |> Enum.filter(&elem(&1, 0))
      |> Map.new(fn {true, field, value} -> {field, value} end)

    if attrs == %{}, do: :ok, else: rewrite(scope, expense_id, transaction, attrs)
  end

  defp rewrite(scope, expense_id, transaction, attrs) do
    with {:ok, _transaction} <-
           Ledger.update_transaction(scope, transaction, attrs, opts(expense_id)) do
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

  @doc "The transaction an expense is linked to, with its category, for the budget owner; nil for none."
  def transaction_for(%Scope{} = scope, expense_id) do
    Access.check!(scope)
    if Scope.budget_owner?(scope), do: linked_to(scope, expense_id)
  end

  defp linked_to(scope, expense_id),
    do: scope |> linked_transaction(expense_id) |> Repo.preload(:category)

  defp owner!(scope) do
    Access.check!(scope)
    if !Scope.budget_owner?(scope), do: raise(AccessError)
  end
end
