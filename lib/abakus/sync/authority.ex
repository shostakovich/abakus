defmodule Abakus.Sync.Authority do
  @moduledoc """
  What a device may not change (ADR 0020, `sync/PROTOCOL.md`). Only the server writes a transaction's `led_by` and
  `matched_transaction_id` and an account's `shared_expenses`. A transaction a source leads, itself or through its
  transfer counterpart, keeps the fields its source leads, and a part of one keeps all of its fields; a transaction or
  part the messages would join to one, as its counterpart or its part, keeps the field that would join it. A device's
  message for such a field is not applied, and the server writes the field again, so the device converges back. A
  part a device adds to a led transaction is created and deleted again.
  """

  import Ecto.Query

  alias Abakus.Ledger.{Account, Subtransaction, Transaction}
  alias Abakus.{Repo, Sync}

  @led [
    :account_id,
    :date,
    :amount,
    :payee_id,
    :transfer_transaction_id,
    :transfer_subtransaction_id,
    :deleted_at
  ]

  @server_written [:led_by, :matched_transaction_id]

  @doc """
  Sorts the messages, the newest one of each field, into `{applied, refused, undone}`: the messages to apply, the
  refused fields as `{schema, id, fields}` and the new rows to delete again as `{schema, id}`.
  """
  def check(messages) do
    rows = Enum.group_by(messages, &{&1.schema, &1.row_id})
    stored = stored(rows)

    Enum.reduce(rows, {[], [], []}, fn {{schema, id}, row_messages}, {applied, refused, undone} ->
      {refusing, undo?} = refusing(schema, id, row_messages, stored)
      {refused_here, applied_here} = Enum.split_with(row_messages, &refused?(&1.field, refusing))

      {applied_here ++ applied, put_refused(refused, schema, id, refused_here),
       if(undo?, do: [{schema, id} | undone], else: undone)}
    end)
  end

  defp refusing(Transaction, id, messages, stored) do
    cond do
      led?(stored, id) ->
        {@server_written ++ @led, false}

      led?(stored, value(messages, :transfer_transaction_id)) ->
        {[:transfer_transaction_id | @server_written], false}

      true ->
        {@server_written, false}
    end
  end

  defp refusing(Subtransaction, id, messages, stored) do
    joining =
      if led?(stored, value(messages, :transfer_transaction_id)),
        do: [:transfer_transaction_id],
        else: []

    cond do
      led?(stored, stored.parts[id]) -> {:all, false}
      not led?(stored, value(messages, :transaction_id)) -> {joining, false}
      Map.has_key?(stored.parts, id) -> {[:transaction_id | joining], false}
      true -> {joining, true}
    end
  end

  defp refusing(Account, _id, _messages, _stored), do: {[:shared_expenses], false}
  defp refusing(_schema, _id, _messages, _stored), do: {[], false}

  defp refused?(_field, :all), do: true
  defp refused?(field, fields), do: field in fields

  defp put_refused(refused, _schema, _id, []), do: refused

  defp put_refused(refused, schema, id, messages),
    do: [{schema, id, Enum.map(messages, & &1.field)} | refused]

  defp value(messages, field) do
    case Enum.find(messages, &(&1.field == field)) do
      nil -> nil
      message -> message.decoded
    end
  end

  defp led?(_stored, nil), do: false

  defp led?(%{transactions: transactions}, id) do
    case transactions[id] do
      nil ->
        false

      transaction ->
        counterpart = transactions[transaction.transfer_transaction_id]
        led_itself?(transaction) or (counterpart != nil and led_itself?(counterpart))
    end
  end

  # A source that is gone nulls its reference, but its tombstone stays led.
  defp led_itself?(transaction),
    do: transaction.led_by != nil or Transaction.led_by(transaction) != nil

  defp stored(rows) do
    parts =
      rows
      |> ids(Subtransaction)
      |> in_chunks(
        &Repo.all(from s in Subtransaction, where: s.id in ^&1, select: {s.id, s.transaction_id})
      )
      |> Map.new()

    named =
      for {{schema, id}, messages} <- rows,
          transaction_id <- named_transactions(schema, id, messages, parts),
          do: transaction_id

    transactions = transactions(named)
    counterparts = transactions |> Map.values() |> Enum.map(& &1.transfer_transaction_id)
    %{parts: parts, transactions: Map.merge(transactions(counterparts), transactions)}
  end

  defp named_transactions(Transaction, id, messages, _parts),
    do: [id, value(messages, :transfer_transaction_id)]

  defp named_transactions(Subtransaction, id, messages, parts),
    do: [parts[id], value(messages, :transaction_id), value(messages, :transfer_transaction_id)]

  defp named_transactions(_schema, _id, _messages, _parts), do: []

  defp ids(rows, schema), do: for({{^schema, id}, _messages} <- rows, do: id)

  defp transactions(ids) do
    ids
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> in_chunks(&Repo.all(from t in Transaction, where: t.id in ^&1))
    |> Map.new(&{&1.id, &1})
  end

  defp in_chunks(values, query), do: values |> Enum.chunk_every(1000) |> Enum.flat_map(query)

  @doc "Writes the refused fields again and deletes the undone rows, as part of a write."
  def restore(refused, undone) do
    for {schema, id, fields} <- refused, do: Sync.rewrite(schema, id, fields)

    for {schema, ids} <- Enum.group_by(undone, &elem(&1, 0), &elem(&1, 1)),
        do: Sync.delete_all(from r in schema, where: r.id in ^ids)

    :ok
  end
end
