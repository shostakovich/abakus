defmodule Abakus.Ledger.Scheduled do
  @moduledoc """
  The Ledger's scheduled transactions (`Abakus.Ledger.ScheduledTransaction`), each the scope's user's: listed,
  created, changed and deleted as tombstones, entered or skipped.

  Every day `Abakus.Ledger.Scheduled.Job` enters them: each occurrence up to today becomes a transaction, unapproved
  for review, whose id is named after the scheduled transaction and the date (`Abakus.Ids.entered_transaction/2`), so
  an occurrence another writer entered already is not entered twice, and its parts and counterparts are named after it
  too. The next date then moves on; one that happens once is deleted once entered. A scheduled transaction the Ledger
  refuses to enter stays due and is reported, its other occurrences wait; one of a closed account waits as it is
  until the account is reopened. "Jetzt buchen" (`enter_now/2`) enters the next occurrence alike, but approved, and
  "Überspringen" (`skip/2`) moves on without entering it.
  """

  import Abakus.Owned
  import Ecto.Query

  alias Abakus.{Ids, Ledger, References, Repo, Sync}
  alias Abakus.Ledger.{Account, ScheduledSubtransaction, ScheduledTransaction, Transaction}
  alias Abakus.Ledger.Transfers
  alias Abakus.Users.Scope
  alias Ecto.Changeset

  @doc """
  The account's scheduled transactions, or with `:all` every account's, by next date, with payee, category and
  parts; `without_accounts:` leaves out those accounts.
  """
  def list(%Scope{} = scope, register, opts \\ []) do
    from(s in live(scope),
      order_by: [s.next_date, s.id],
      preload: [:payee, :category, subtransactions: [:payee, :category]]
    )
    |> in_register(register)
    |> without_accounts(opts[:without_accounts] || [])
    |> Repo.all()
  end

  defp in_register(query, %Account{id: id}), do: where(query, [s], s.account_id == ^id)
  defp in_register(query, :all), do: query

  defp without_accounts(query, []), do: query
  defp without_accounts(query, ids), do: where(query, [s], s.account_id not in ^ids)

  defp live(scope), do: from(s in owned(ScheduledTransaction, scope), where: is_nil(s.deleted_at))

  @doc "The scheduled transaction with what its form needs (payees, parts), nil for one that is gone."
  def get(%Scope{} = scope, id) do
    with {:ok, id} <- Ids.cast(id),
         %ScheduledTransaction{} = scheduled <- Repo.get(live(scope), id) do
      Repo.preload(scheduled, [:payee, subtransactions: :payee])
    else
      _gone -> nil
    end
  end

  @doc """
  Creates a scheduled transaction, with parts (`subtransactions`) for a split; the payee may be given by name, as for
  `Abakus.Ledger.create_transaction/3`. Refuses references that are not the user's and what could not be entered
  (`Abakus.Ledger.ScheduledTransaction.validate_accounts/3`).
  """
  def create(%Scope{} = scope, attrs) do
    Sync.write(fn ->
      with {:ok, attrs} <- Ledger.put_payee_by_name(scope, attrs) do
        %ScheduledTransaction{user_id: user_id(scope)}
        |> ScheduledTransaction.changeset(attrs)
        |> validate(scope)
        |> Sync.insert()
      end
    end)
  end

  @doc """
  Changes a scheduled transaction as `create/2` makes one; the parts it no longer has are deleted as tombstones, and
  a change of its repeat writes both of its fields. `{:error, :not_found}` for one that is gone.
  """
  def update(%Scope{} = scope, %ScheduledTransaction{id: id}, attrs) do
    Sync.write(fn ->
      with {:ok, scheduled} <- fetch(scope, id),
           {:ok, attrs} <- Ledger.put_payee_by_name(scope, attrs) do
        scheduled |> ScheduledTransaction.changeset(attrs) |> validate(scope) |> save()
      end
    end)
  end

  defp save(changeset) do
    {changeset, removed} = Transaction.take_removed_subtransactions(changeset)

    with {:ok, updated} <- Sync.update(changeset) do
      Sync.delete_all(from s in ScheduledSubtransaction, where: s.id in ^removed)
      rewrite_repeat(changeset)
      {:ok, updated}
    end
  end

  # Unit and count step together, so a writer that changes one writes both with one clock.
  defp rewrite_repeat(%Changeset{data: %{id: id}} = changeset) do
    if Changeset.changed?(changeset, :repeat_unit) or Changeset.changed?(changeset, :repeat_every),
      do: Sync.rewrite(ScheduledTransaction, id, [:repeat_unit, :repeat_every]),
      else: :ok
  end

  @doc "Deletes a scheduled transaction as a tombstone; `{:error, :not_found}` for one that is gone."
  def delete(%Scope{} = scope, %ScheduledTransaction{id: id}) do
    Sync.write(fn ->
      with {:ok, scheduled} <- fetch(scope, id), do: tombstone(scheduled)
    end)
  end

  @doc """
  "Jetzt buchen": enters the next occurrence as the daily job does, with the same id, but approved, then moves on.
  An occurrence entered already only moves on. Returns the scheduled transaction as it is then, nil once it is
  deleted.
  """
  def enter_now(%Scope{} = scope, %ScheduledTransaction{id: id}) do
    Sync.write(fn ->
      with {:ok, scheduled} <- fetch(scope, id),
           {:ok, _count} <- enter(scope, scheduled, true),
           do: move_on(scheduled)
    end)
  end

  @doc "\"Überspringen\": moves on to the following occurrence without entering this one; one that happens once goes."
  def skip(%Scope{} = scope, %ScheduledTransaction{id: id}) do
    Sync.write(fn ->
      with {:ok, scheduled} <- fetch(scope, id), do: move_on(scheduled)
    end)
  end

  defp fetch(scope, id) do
    case Repo.one(from s in live(scope), where: s.id == ^id, preload: :subtransactions) do
      nil -> {:error, :not_found}
      scheduled -> {:ok, scheduled}
    end
  end

  defp validate(changeset, scope) do
    changeset = validate_references(changeset, scope)
    account_id = Changeset.get_field(changeset, :account_id)

    case account_id && Repo.get(owned(Account, scope), account_id) do
      nil ->
        changeset

      account ->
        payee_ids =
          Enum.map(
            [changeset | Transaction.subtransactions(changeset)],
            &Changeset.get_field(&1, :payee_id)
          )

        transfer_accounts = Transfers.accounts_by_payee(user_id(scope), payee_ids)
        ScheduledTransaction.validate_accounts(changeset, account, transfer_accounts)
    end
  end

  defp validate_references(changeset, scope) do
    changeset
    |> References.validate_exists(:account_id, owned(Account, scope))
    |> Ledger.validate_references(user_id(scope))
  end

  @doc """
  Enters the scope's occurrences due by `today`, except those of closed accounts, which wait until it is reopened;
  `{:ok, entered}` with the number of transactions entered, or `{:error, entered, reasons}` when some were refused.
  """
  def enter_due(%Scope{} = scope, %Date{} = today) do
    {entered, errors} =
      from(s in live(scope),
        join: a in assoc(s, :account),
        where: s.next_date <= ^today and not a.closed,
        order_by: [s.next_date, s.id]
      )
      |> Repo.all()
      |> Enum.reduce({0, []}, &enter_each(&1, &2, scope, today))

    if errors == [], do: {:ok, entered}, else: {:error, entered, Enum.reverse(errors)}
  end

  defp enter_each(listed, {entered, errors}, scope, today) do
    case Sync.write(fn -> catch_up_current(listed, scope, today) end) do
      {:ok, count} -> {entered + count, errors}
      {:error, reason} -> {entered, [failure(listed, reason) | errors]}
    end
  end

  defp catch_up_current(listed, scope, today) do
    case fetch(scope, listed.id) do
      {:ok, scheduled} -> catch_up(scheduled, scope, today, 0)
      {:error, :not_found} -> {:ok, 0}
    end
  end

  defp catch_up(nil = _entered_once, _scope, _today, entered), do: {:ok, entered}

  defp catch_up(scheduled, scope, today, entered) do
    if Date.after?(scheduled.next_date, today),
      do: {:ok, entered},
      else: enter_next(scheduled, scope, today, entered)
  end

  defp enter_next(scheduled, scope, today, entered) do
    with {:ok, count} <- enter(scope, scheduled, false),
         {:ok, moved} <- move_on(scheduled),
         do: catch_up(moved, scope, today, entered + count)
  end

  defp enter(scope, %ScheduledTransaction{id: id, next_date: date} = scheduled, approved) do
    if Repo.exists?(where(Transaction, id: ^Ids.entered_transaction(id, date))) do
      {:ok, 0}
    else
      with {:ok, _transaction} <-
             Ledger.create_transaction(scope, attrs(scheduled, approved),
               entered_from: {id, date}
             ),
           do: {:ok, 1}
    end
  end

  defp attrs(scheduled, approved) do
    scheduled
    |> Map.take([:account_id, :payee_id, :category_id, :memo, :amount, :cleared])
    |> Map.merge(%{
      date: scheduled.next_date,
      source: :scheduled,
      approved: approved,
      subtransactions:
        Enum.map(
          scheduled.subtransactions,
          &Map.take(&1, [:amount, :payee_id, :category_id, :memo])
        )
    })
  end

  defp move_on(scheduled) do
    case ScheduledTransaction.following(scheduled) do
      nil ->
        with {:ok, _deleted} <- tombstone(scheduled), do: {:ok, nil}

      date ->
        scheduled |> Changeset.change(next_date: date) |> Sync.update()
    end
  end

  defp tombstone(scheduled),
    do: scheduled |> Changeset.change(deleted_at: DateTime.utc_now()) |> Sync.update()

  defp failure(scheduled, %Changeset{} = changeset),
    do: failure(scheduled, inspect(Changeset.traverse_errors(changeset, &elem(&1, 0))))

  defp failure(scheduled, reason),
    do: "scheduled transaction #{scheduled.id} on #{scheduled.next_date}: #{reason}"
end
