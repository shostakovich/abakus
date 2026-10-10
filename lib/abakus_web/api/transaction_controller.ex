defmodule AbakusWeb.Api.TransactionController do
  @moduledoc """
  An account's transactions, and creating, changing and deleting them. Writes are all or none; a change the Ledger
  refuses because it alters a reconciled transaction answers 409. Match proposals count nowhere, so the API does not
  know them; a deleted transaction is reported as such and not changed, as YNAB does.
  """

  use AbakusWeb, :controller

  alias Abakus.Ledger
  alias Abakus.Ledger.Transaction
  alias Abakus.Schema
  alias AbakusWeb.Api
  alias AbakusWeb.Api.{TransactionParams, YnabJSON}

  action_fallback AbakusWeb.Api.FallbackController

  def index(conn, %{"account_id" => account_id} = params) do
    with {:ok, account} <- Api.find_account(account_id),
         {:ok, since} <- since_date(params) do
      transactions = account |> Ledger.list_transactions(since: since) |> Enum.reverse()

      json(conn, %{
        data: %{
          transactions: Enum.map(transactions, &YnabJSON.transaction/1),
          server_knowledge: 0
        }
      })
    end
  end

  defp since_date(%{"since_date" => date}) do
    case is_binary(date) && Date.from_iso8601(date) do
      {:ok, date} -> {:ok, date}
      _invalid -> {:error, "since_date muss ein Datum wie 2026-10-01 sein"}
    end
  end

  defp since_date(_params), do: {:ok, nil}

  def create(conn, params) do
    with {:ok, attrs} <- TransactionParams.for_create(params),
         {:ok, created} <-
           Ledger.create_transactions(Enum.map(attrs, &Map.put(&1, "source", "api"))) do
      conn
      |> put_status(:created)
      |> saved(Enum.map(created, & &1.id))
    end
  end

  def update(conn, params) do
    with {:ok, changes} <- TransactionParams.for_update(params),
         {:ok, changes} <- find_changed(changes),
         {:ok, _changed} <-
           changes |> Enum.reject(&deleted?/1) |> Ledger.update_each_transaction() do
      saved(conn, Enum.map(changes, fn {transaction, _attrs} -> transaction.id end))
    end
  end

  defp find_changed(changes) do
    found =
      changes |> Enum.flat_map(fn {id, _attrs} -> cast_id(id) end) |> Ledger.get_transactions()

    changes = Enum.map(changes, fn {id, attrs} -> {known(found, id), attrs} end)

    if Enum.any?(changes, &match?({nil, _attrs}, &1)),
      do: {:error, :not_found},
      else: {:ok, changes}
  end

  defp deleted?({%Transaction{deleted_at: deleted_at}, _attrs}), do: not is_nil(deleted_at)

  def delete(conn, %{"transaction_id" => id}) do
    found = id |> cast_id() |> Ledger.get_transactions()

    with %Transaction{deleted_at: nil} = transaction <- known(found, id),
         {:ok, deleted} <- Ledger.delete_transaction(transaction) do
      json(conn, %{data: %{transaction: transaction_json(deleted.id), server_knowledge: 0}})
    else
      %Transaction{} -> {:error, :not_found}
      nil -> {:error, :not_found}
      error -> error
    end
  end

  # The transaction a client's id names, unless it is a match proposal.
  defp known(found, id) do
    with [id] <- cast_id(id),
         %Transaction{matched_transaction_id: nil} = transaction <- Map.get(found, id) do
      transaction
    else
      _ -> nil
    end
  end

  defp cast_id(id) do
    case Schema.cast_id(id) do
      {:ok, id} -> [id]
      :error -> []
    end
  end

  defp saved(conn, ids) do
    found = Ledger.get_transactions(ids)
    transactions = Enum.map(ids, &YnabJSON.transaction(Map.fetch!(found, &1)))

    json(conn, %{
      data: %{
        transaction_ids: Enum.map(transactions, & &1.id),
        transactions: transactions,
        server_knowledge: 0
      }
    })
  end

  defp transaction_json(id),
    do: [id] |> Ledger.get_transactions() |> Map.fetch!(id) |> YnabJSON.transaction()
end
