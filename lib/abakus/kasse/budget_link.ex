defmodule Abakus.Kasse.BudgetLink do
  @moduledoc """
  Expenses linked to the budget (ADR 0006). A linked participant (the budget owner, once switched on) has their
  share of every expense as a transaction in the account fed by `shared_expenses`, written through the Ledger in
  the expense's database transaction: minus the share, dated as the expense, the title as payee, the budget category
  the Kasse category is mapped to, a memo describing the expense, created cleared and unapproved. Reimbursements and
  expenses without a share of theirs give none.

  The Kasse leads on what it changes: amount, date and payee follow every change of the expense. The register may
  change category, memo, flag, cleared state and approval; a later Kasse change keeps a category or memo the
  register changed, but a change of the Kasse category always writes the mapped category.

  The link's tables stay out of the MCP's SQL sandbox, as they point into the budget.
  """

  import Ecto.Query

  alias Abakus.Categories.Category, as: BudgetCategory
  alias Abakus.Kasse.BudgetLink.{CategoryMapping, Link, LinkedTransaction}
  alias Abakus.Kasse.Categories.Category
  alias Abakus.Kasse.Expenses.Expense
  alias Abakus.Kasse.Money
  alias Abakus.Kasse.Participants.Participant
  alias Abakus.Ledger
  alias Abakus.Ledger.{Account, Transaction}
  alias Abakus.Repo
  alias Ecto.Changeset

  @register_fields [:category_id, :memo, :flag, :cleared, :approved]

  @doc "The fields of a linked transaction the register may change."
  def register_fields, do: @register_fields

  @doc "The open account fed by `shared_expenses` that linked shares go to, the first in order; nil without one."
  def shared_expenses_account do
    Repo.one(
      from a in Account,
        where: a.fed_by == :shared_expenses and not a.closed,
        order_by: [a.position, a.id],
        limit: 1
    )
  end

  @doc """
  Links the participant to the budget: from now on their shares are booked in the shared-expenses account. Only the
  budget owner's participant can be linked; `{:error, :no_account}` without a shared-expenses account.
  """
  def switch_on(%Participant{} = participant) do
    participant = Repo.preload(participant, :user)

    cond do
      not participant.user.budget_owner ->
        {:error, :not_budget_owner}

      account = shared_expenses_account() ->
        Repo.insert(%Link{participant_id: participant.id, account_id: account.id},
          on_conflict: {:replace, [:account_id, :updated_at]},
          conflict_target: :participant_id
        )

      true ->
        {:error, :no_account}
    end
  end

  @doc "The account the participant's shares are booked in; nil while they are not linked."
  def account(%Participant{id: id}) do
    Repo.one(
      from l in Link, join: a in assoc(l, :account), where: l.participant_id == ^id, select: a
    )
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
      {nil, nil} -> :ok
      {nil, wanted} -> create(link, expense_id, wanted)
      {linked, nil} -> remove(linked)
      {linked, wanted} -> change(linked, wanted(old, link), wanted)
    end
  end

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
    total = "Gesamt " <> Money.format_cents(expense.amount_cents)

    total =
      if Expense.foreign?(expense),
        do:
          total <> " (#{Money.format_money(expense.original_amount, expense.original_currency)})",
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
      Repo.insert!(%LinkedTransaction{
        expense_id: expense_id,
        participant_id: link.participant_id,
        transaction_id: transaction.id,
        written_category_id: transaction.category_id,
        written_memo: transaction.memo
      })

      :ok
    end
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
  def category_mapping do
    Repo.all(from m in CategoryMapping, select: {m.category_id, m.budget_category_id})
    |> Map.new()
  end

  @doc """
  Maps Kasse categories to budget categories: budget category ids (nil or `""` for none) by Kasse category id,
  also as text; Kasse categories left out keep theirs. Only regular budget categories can be chosen.
  """
  def put_category_mapping(mapping) do
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

      {:ok, category_mapping()}
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

  @doc "The transaction an expense is linked to, with its category; nil for none."
  def transaction_for(expense_id) do
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
end
