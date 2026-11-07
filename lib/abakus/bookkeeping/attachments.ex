defmodule Abakus.Bookkeeping.Attachments do
  @moduledoc """
  The attachments of the user's transactions: documents in their Paperless that a transaction, or a part of its split,
  links to (`Abakus.Bookkeeping.Attachment`), and the mark that a transaction needs none
  (`Abakus.Bookkeeping.ReceiptWaiver`). An upload goes to Paperless, which takes a file it has already as that
  document. Paperless is the archive (ADR 0033); Abakus keeps only the link and the title.

  Proposed as a transaction's attachment are the Paperless documents whose text has the transaction's amount, in German
  or English notation, which were created from a month before it to a week after, and which no transaction or part in
  the register has attached, the closest first.
  """

  import Ecto.Query
  import Abakus.Owned
  import Abakus.JsonList

  alias Abakus.{Bookkeeping, Ledger, Money, Paperless, Repo}
  alias Abakus.Bookkeeping.{Attachment, ReceiptWaiver}
  alias Abakus.Ledger.{Subtransaction, Transaction}
  alias Abakus.Users.Scope

  @days_before 31
  @days_after 7
  @proposals 10

  @doc """
  The sides of a transaction that take attachments: `nil` for the whole transaction, and for a split each part that
  takes a tax line; none for a transfer. Needs the subtransactions.
  """
  def sides(%Transaction{} = transaction) do
    case Bookkeeping.sides(transaction) do
      [] -> []
      [nil] -> [nil]
      parts -> [nil | parts]
    end
  end

  @doc """
  The attachments of `transactions` that count, by `{transaction_id, side}` as `sides/1` names the sides, in the order
  they were attached. Needs their subtransactions.
  """
  def list(%Scope{} = scope, transactions) do
    counting = MapSet.new(for t <- transactions, side <- sides(t), do: {t.id, side})

    Repo.all(
      from a in owned(Attachment, scope),
        where: in_json(a.transaction_id, ids(transactions)),
        order_by: [asc: a.inserted_at, asc: a.id]
    )
    |> Enum.group_by(&{&1.transaction_id, &1.subtransaction_id})
    |> Map.filter(fn {key, _attachments} -> key in counting end)
  end

  @doc "The ids of those of `transactions` that need no attachment."
  def waived(%Scope{} = scope, transactions) do
    Repo.all(
      from w in owned(ReceiptWaiver, scope),
        where: in_json(w.transaction_id, ids(transactions)),
        select: w.transaction_id
    )
    |> MapSet.new()
  end

  @doc """
  Marks the user's transaction as needing no attachment, or as needing one again; `{:error, :not_found}` when it is not
  in their register.
  """
  def waive(%Scope{} = scope, %Transaction{} = transaction, true) do
    with {:ok, %Transaction{id: id}} <- owned_transaction(scope, transaction) do
      Repo.insert!(%ReceiptWaiver{user_id: user_id(scope), transaction_id: id},
        on_conflict: :nothing,
        conflict_target: :transaction_id
      )

      :ok
    end
  end

  def waive(%Scope{} = scope, %Transaction{id: id}, false) do
    Repo.delete_all(from w in owned(ReceiptWaiver, scope), where: w.transaction_id == ^id)
    :ok
  end

  @doc """
  The Paperless documents proposed as the transaction's attachment, at most ten. `{:error, :not_connected}` without a
  Paperless connection, else Paperless's error.
  """
  def proposals(%Scope{} = scope, %Transaction{amount: 0}),
    do: with_connection(scope, fn _c -> {:ok, []} end)

  def proposals(%Scope{} = scope, %Transaction{} = transaction) do
    with_connection(scope, fn connection ->
      from = Date.add(transaction.date, -@days_before)
      to = Date.add(transaction.date, @days_after)

      with {:ok, documents} <- search(connection, notations(transaction.amount), from, to) do
        {:ok, documents |> unattached(scope) |> closest(transaction.date)}
      end
    end)
  end

  @doc ~s{How an amount may be written in a document: −1.234,56 € as "1.234,56", "1234,56", "1,234.56" and "1234.56".}
  def notations(cents) do
    german = Money.amount(abs(cents))

    english =
      String.replace(german, [".", ","], fn
        "." -> ","
        "," -> "."
      end)

    Enum.uniq([
      german,
      String.replace(german, ".", ""),
      english,
      String.replace(english, ",", "")
    ])
  end

  defp search(connection, texts, from, to) do
    Enum.reduce_while(texts, {:ok, []}, fn text, {:ok, found} ->
      case Paperless.client().search(connection, text, from, to) do
        {:ok, documents} -> {:cont, {:ok, found ++ documents}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp unattached(documents, scope) do
    documents = Enum.uniq_by(documents, & &1.id)
    ids = Enum.map(documents, & &1.id)

    attached =
      Repo.all(
        from a in owned(Attachment, scope),
          join: t in ^Ledger.in_register(scope),
          on: t.id == a.transaction_id,
          left_join: s in Subtransaction,
          on: s.id == a.subtransaction_id,
          where: in_json(a.paperless_id, ids),
          where: is_nil(a.subtransaction_id) or (not is_nil(s.id) and is_nil(s.deleted_at)),
          select: a.paperless_id
      )

    Enum.reject(documents, &(&1.id in attached))
  end

  defp closest(documents, date) do
    documents
    |> Enum.sort_by(&if(&1.created, do: abs(Date.diff(&1.created, date)), else: @days_before + 1))
    |> Enum.take(@proposals)
  end

  @doc """
  Attaches the Paperless document with `paperless_id` to a side of the user's transaction, `nil` for the whole; one
  attached there already stays as it is. `{:error, :not_found}` when the transaction is no longer in the register,
  `{:error, :side}` for a side it does not have, `{:error, :not_connected}` without Paperless, else Paperless's error.
  """
  def attach(%Scope{} = scope, %Transaction{} = transaction, side, paperless_id) do
    with {:ok, transaction} <- current(scope, transaction, side),
         {:ok, connection} <- Paperless.connection(scope),
         {:ok, document} <- Paperless.client().document(connection, paperless_id) do
      insert(scope, transaction, side, document)
    end
  end

  @doc """
  Files `content` in the user's Paperless as `filename` and attaches its document, as `attach/4` does; a file
  Paperless has already is attached as that document. `{:error, :consuming}` when Paperless takes too long, the file
  may still arrive there.
  """
  def upload(%Scope{} = scope, %Transaction{} = transaction, side, content, filename) do
    with {:ok, transaction} <- current(scope, transaction, side),
         {:ok, connection} <- Paperless.connection(scope),
         {:ok, id} <- Paperless.client().upload(connection, content, filename),
         {:ok, document} <- Paperless.client().document(connection, id) do
      insert(scope, transaction, side, document)
    end
  end

  @doc """
  Attaches the document with `paperless_id`, titled `title`, to the whole of the user's transaction, unless it is
  there already: a file Abakus filed in Paperless itself, such as a Lexoffice receipt's. `{:error, :not_found}` when
  the transaction is not in the user's register.
  """
  def link(%Scope{} = scope, %Transaction{} = transaction, paperless_id, title) do
    with {:ok, transaction} <- owned_transaction(scope, transaction),
         do: insert(scope, transaction, nil, %{id: paperless_id, title: title})
  end

  defp current(scope, transaction, side) do
    with {:ok, transaction} <- owned_transaction(scope, transaction) do
      if side in sides(transaction), do: {:ok, transaction}, else: {:error, :side}
    end
  end

  defp owned_transaction(scope, %Transaction{id: id}) do
    case Bookkeeping.get_transaction(scope, id) do
      nil -> {:error, :not_found}
      transaction -> {:ok, transaction}
    end
  end

  defp insert(scope, transaction, side, document) do
    existing =
      Repo.one(
        from a in owned(Attachment, scope),
          where: a.transaction_id == ^transaction.id and a.paperless_id == ^document.id,
          where: ^side_condition(side)
      )

    case existing do
      nil ->
        Repo.insert(%Attachment{
          user_id: user_id(scope),
          transaction_id: transaction.id,
          subtransaction_id: side,
          paperless_id: document.id,
          title: title(document)
        })

      attachment ->
        {:ok, attachment}
    end
  end

  defp side_condition(nil), do: dynamic([a], is_nil(a.subtransaction_id))
  defp side_condition(part_id), do: dynamic([a], a.subtransaction_id == ^part_id)

  defp title(document) do
    Enum.find([document[:title], document[:filename]], &(&1 not in [nil, ""])) ||
      "Paperless #{document.id}"
  end

  @doc "Removes the user's attachment with `id` from its transaction; the document stays in Paperless."
  def detach(%Scope{} = scope, id) do
    case Abakus.Ids.cast(id) do
      {:ok, id} -> Repo.delete_all(from a in owned(Attachment, scope), where: a.id == ^id)
      :error -> :ok
    end

    :ok
  end

  @doc "The document with `paperless_id` in the user's Paperless, with its title, date and text."
  def document(%Scope{} = scope, paperless_id),
    do: with_connection(scope, &Paperless.client().document(&1, paperless_id))

  @doc "The PDF of the document with `paperless_id` in the user's Paperless."
  def download(%Scope{} = scope, paperless_id),
    do: with_connection(scope, &Paperless.client().download(&1, paperless_id))

  defp with_connection(scope, fun) do
    with {:ok, connection} <- Paperless.connection(scope), do: fun.(connection)
  end
end
