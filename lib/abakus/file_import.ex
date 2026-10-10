defmodule Abakus.FileImport do
  @moduledoc """
  The file import: the statements of an OFX/QFX file (`Abakus.FileImport.OFX`) into accounts. An account remembers
  the file's account (`BANKID`, `ACCTID`) once a statement went into it, so the next file finds it.

  Transactions land unapproved and cleared, from source `file` with their FITID as external id; a FITID the account
  has already (deleted transactions included) is not imported again, nor one that a file repeats. The payee comes
  from `NAME` (the regular payee with its lookup key, else a new one), the memo from `MEMO`. The statement's ledger
  balance becomes the account's bank balance from the file.

  Accounts fed by another app and closed ones take no file import.
  """

  alias Abakus.FileImport.OFX
  alias Abakus.{Ledger, Repo}
  alias Abakus.Ledger.Account

  @doc "The statements of a file, or why it cannot be read."
  defdelegate read(content), to: OFX, as: :parse

  @doc "The accounts a statement can go into, in their order."
  def accounts, do: Enum.filter(Ledger.list_accounts(), &Account.takes_entries?/1)

  @doc "The account the statement's account is linked to, as long as it takes a file import."
  def linked_account(%{bank_id: bank_id, acct_id: acct_id}) do
    account = Ledger.get_account_by_ofx(bank_id, acct_id)
    if account && Account.takes_entries?(account), do: account
  end

  @doc """
  The statement's transactions, each `:new` or `:existing` in the account (all new without one), and how many are
  which.
  """
  def preview(statement, account) do
    transactions = unique(statement.transactions)
    existing = existing_fitids(account, transactions)

    rows =
      Enum.map(transactions, fn transaction ->
        status = if transaction.fitid in existing, do: :existing, else: :new
        %{transaction: transaction, status: status}
      end)

    %{
      rows: rows,
      new: Enum.count(rows, &(&1.status == :new)),
      existing: Enum.count(rows, &(&1.status == :existing))
    }
  end

  defp unique(transactions), do: Enum.uniq_by(transactions, & &1.fitid)

  defp existing_fitids(nil, _transactions), do: MapSet.new()

  defp existing_fitids(account, transactions),
    do: Ledger.existing_external_ids(account, :file, Enum.map(transactions, & &1.fitid))

  @doc """
  Imports `{statement, account}` pairs, all or none, and returns how many transactions came in. Refuses an account
  that takes no file import or two statements into one account with a message, a transaction the Ledger refuses
  with `{transaction, changeset}`.
  """
  def import(statements) do
    Repo.transact(fn ->
      with {:ok, statements} <- fresh_accounts(statements) do
        sum(statements, &import_statement/1)
      end
    end)
  end

  defp fresh_accounts(statements) do
    statements =
      Enum.map(statements, fn {statement, %Account{id: id}} ->
        {statement, Ledger.get_account!(id)}
      end)

    accounts = Enum.map(statements, &elem(&1, 1))

    cond do
      account = Enum.find(accounts, &(not Account.takes_entries?(&1))) ->
        {:error, "#{account.name} nimmt keinen Datei-Import."}

      length(Enum.uniq_by(accounts, & &1.id)) < length(accounts) ->
        {:error, "Zwei Konten der Datei gehen nicht in dasselbe Konto."}

      true ->
        {:ok, statements}
    end
  end

  defp import_statement({statement, account}) do
    with {:ok, account} <- Ledger.link_ofx_account(account, statement.bank_id, statement.acct_id),
         {:ok, count} <- import_transactions(statement, account),
         :ok <- put_bank_balance(account, statement.ledger_balance) do
      {:ok, count}
    end
  end

  defp import_transactions(statement, account) do
    new =
      for %{status: :new, transaction: transaction} <- preview(statement, account).rows,
          do: transaction

    sum(new, &create(account, &1))
  end

  defp create(account, transaction) do
    attrs = %{
      account_id: account.id,
      date: transaction.date,
      amount: transaction.amount,
      payee_name: transaction.name,
      memo: transaction.memo,
      cleared: :cleared,
      source: :file
    }

    with {:ok, created} <- Ledger.create_transaction(attrs),
         {:ok, _origin} <- Ledger.add_origin(created, :file, transaction.fitid) do
      {:ok, 1}
    else
      {:error, changeset} -> {:error, {transaction, changeset}}
    end
  end

  defp put_bank_balance(_account, nil), do: :ok

  defp put_bank_balance(account, balance) do
    with {:ok, _balance} <- Ledger.put_bank_balance(account, Map.put(balance, :source, :file)),
         do: :ok
  end

  # Adds up the counts `fun` returns, until it refuses one.
  defp sum(items, fun) do
    Enum.reduce_while(items, {:ok, 0}, fn item, {:ok, total} ->
      case fun.(item) do
        {:ok, count} -> {:cont, {:ok, total + count}}
        error -> {:halt, error}
      end
    end)
  end
end
