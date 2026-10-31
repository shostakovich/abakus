defmodule Abakus.Ledger.Scheduled do
  @moduledoc """
  Enters scheduled transactions (`Abakus.Ledger.ScheduledTransaction`), every day by `Abakus.Ledger.Scheduled.Job`:
  each occurrence up to today becomes a transaction, unapproved for review, whose id is named after the scheduled
  transaction and the date (`Abakus.Ids.entered_transaction/2`), so an occurrence another writer entered already
  is not entered twice, and its parts and counterparts are named after it too. The next date then moves on; one that
  happens once is deleted once entered. A scheduled transaction the Ledger refuses to enter stays due and is
  reported, its other occurrences wait.
  """

  import Abakus.Owned
  import Ecto.Query

  alias Abakus.{Ids, Ledger, Repo, Sync}
  alias Abakus.Ledger.{ScheduledTransaction, Transaction}
  alias Abakus.Users.Scope
  alias Ecto.Changeset

  @doc """
  Enters the scope's occurrences due by `today`; `{:ok, entered}` with the number of transactions entered, or
  `{:error, entered, reasons}` when some were refused.
  """
  def enter_due(%Scope{} = scope, %Date{} = today) do
    {entered, errors} =
      from(s in owned(ScheduledTransaction, scope),
        where: s.next_date <= ^today and is_nil(s.deleted_at),
        order_by: [s.next_date, s.id],
        preload: :subtransactions
      )
      |> Repo.all()
      |> Enum.reduce({0, []}, &enter_each(&1, &2, scope, today))

    if errors == [], do: {:ok, entered}, else: {:error, entered, Enum.reverse(errors)}
  end

  defp enter_each(scheduled, {entered, errors}, scope, today) do
    case Sync.write(fn -> catch_up(scheduled, scope, today, 0) end) do
      {:ok, count} -> {entered + count, errors}
      {:error, reason} -> {entered, [failure(scheduled, reason) | errors]}
    end
  end

  defp catch_up(nil = _entered_once, _scope, _today, entered), do: {:ok, entered}

  defp catch_up(scheduled, scope, today, entered) do
    if Date.after?(scheduled.next_date, today),
      do: {:ok, entered},
      else: enter_next(scheduled, scope, today, entered)
  end

  defp enter_next(scheduled, scope, today, entered) do
    with {:ok, count} <- enter(scope, scheduled),
         {:ok, moved} <- move_on(scheduled),
         do: catch_up(moved, scope, today, entered + count)
  end

  defp enter(scope, %ScheduledTransaction{id: id, next_date: date} = scheduled) do
    if Repo.exists?(where(Transaction, id: ^Ids.entered_transaction(id, date))) do
      {:ok, 0}
    else
      with {:ok, _transaction} <-
             Ledger.create_transaction(scope, attrs(scheduled), entered_from: {id, date}),
           do: {:ok, 1}
    end
  end

  defp attrs(scheduled) do
    scheduled
    |> Map.take([:account_id, :payee_id, :category_id, :memo, :amount, :cleared])
    |> Map.merge(%{
      date: scheduled.next_date,
      source: :scheduled,
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
        now = DateTime.utc_now()

        with {:ok, _deleted} <-
               scheduled |> Changeset.change(deleted_at: now) |> Sync.update(),
             do: {:ok, nil}

      date ->
        scheduled |> Changeset.change(next_date: date) |> Sync.update()
    end
  end

  defp failure(scheduled, %Changeset{} = changeset),
    do: failure(scheduled, inspect(Changeset.traverse_errors(changeset, &elem(&1, 0))))

  defp failure(scheduled, reason),
    do: "scheduled transaction #{scheduled.id} on #{scheduled.next_date}: #{reason}"
end
