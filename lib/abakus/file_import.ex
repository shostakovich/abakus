defmodule Abakus.FileImport do
  @moduledoc """
  The file import: the statements of an OFX/QFX file (`Abakus.FileImport.OFX`) into accounts. An account remembers
  the file's account (`BANKID`, `ACCTID`) once a statement went into it, so the next file finds it.

  Transactions land unapproved and cleared, from source `file` with their FITID as external id; a FITID the account
  has already (deleted transactions included) is not imported again, nor one that a file repeats, nor one dated up
  to the account's newest reconciled transaction. One that looks like a transaction in the register comes in as a
  match proposal for it, never merged silently. The payee comes from `NAME` (the regular payee with its lookup key,
  else a new one), the memo from `MEMO`. The statement's ledger balance becomes the account's bank balance from the
  file.

  The shared-expenses account and closed accounts take no file import. Everything goes through the Ledger with the
  caller's scope.
  """

  alias Abakus.FileImport.OFX
  alias Abakus.{Ledger, Repo}
  alias Abakus.Ledger.Account
  alias Abakus.Users.Scope

  @doc "The statements of a file, or why it cannot be read."
  defdelegate read(content), to: OFX, as: :parse

  @doc "The accounts a statement can go into, in their order."
  def accounts(%Scope{} = scope),
    do: Enum.filter(Ledger.list_accounts(scope), &Account.takes_entries?/1)

  @doc "The account the statement's account is linked to, as long as it takes a file import."
  def linked_account(%Scope{} = scope, %{bank_id: bank_id, acct_id: acct_id}) do
    account = Ledger.get_account_by_ofx(scope, bank_id, acct_id)
    if account && Account.takes_entries?(account), do: account
  end

  @doc """
  The statement's transactions, each with its status in the account and how many have which: `:existing` (its
  FITID is there), `:reconciled` (dated up to the account's newest reconciled transaction, which takes no match, so
  it would come in twice), `:matched` (it proposes a match, see `Abakus.Ledger.find_matches/4`, for `match`) or
  `:new`. Without an account all are new.
  """
  def preview(%Scope{} = scope, statement, account) do
    rows = statement.transactions |> unique() |> rows(scope, account)
    counts = Enum.frequencies_by(rows, & &1.status)

    Map.new([:new, :existing, :matched, :reconciled], &{&1, Map.get(counts, &1, 0)})
    |> Map.put(:rows, rows)
  end

  defp unique(transactions), do: Enum.uniq_by(transactions, & &1.fitid)

  defp rows(transactions, _scope, nil), do: Enum.map(transactions, &row(&1, :new))

  defp rows(transactions, scope, account) do
    fitids = Enum.map(transactions, & &1.fitid)
    existing = Ledger.existing_external_ids(scope, account, :file, fitids)
    reconciled_until = Ledger.last_reconciled_date(scope, account)
    rows = Enum.map(transactions, &row(&1, status(&1, existing, reconciled_until)))
    {open, _others} = Enum.split_with(rows, &(&1.status == :new))
    matches = Ledger.find_matches(scope, account, :file, Enum.map(open, & &1.transaction))

    match_by_fitid =
      open |> Enum.zip(matches) |> Map.new(fn {row, match} -> {row.transaction.fitid, match} end)

    Enum.map(rows, fn row ->
      case match_by_fitid[row.transaction.fitid] do
        nil -> row
        match -> %{row | status: :matched, match: match}
      end
    end)
  end

  defp row(transaction, status), do: %{transaction: transaction, status: status, match: nil}

  defp status(transaction, existing, reconciled_until) do
    cond do
      transaction.fitid in existing -> :existing
      reconciled_until && Date.compare(transaction.date, reconciled_until) != :gt -> :reconciled
      true -> :new
    end
  end

  @doc """
  Imports `{statement, account}` pairs, all or none: the new transactions and the match proposals, which wait for
  "Zuordnen" or "Trennen". Returns how many came in as `%{new, matched}`. Refuses an account that takes no file
  import or two statements into one account with a message, a transaction the Ledger refuses with
  `{transaction, changeset}`.
  """
  def import(%Scope{} = scope, statements) do
    Repo.transact(fn ->
      with {:ok, statements} <- fresh_accounts(scope, statements),
           {:ok, statuses} <- collect(statements, &import_statement(scope, &1)) do
        counts = statuses |> List.flatten() |> Enum.frequencies()
        {:ok, %{new: Map.get(counts, :new, 0), matched: Map.get(counts, :matched, 0)}}
      end
    end)
  end

  defp fresh_accounts(scope, statements) do
    statements =
      Enum.map(statements, fn {statement, %Account{id: id}} ->
        {statement, Ledger.get_account!(scope, id)}
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

  defp import_statement(scope, {statement, account}) do
    with {:ok, account} <-
           Ledger.link_ofx_account(scope, account, statement.bank_id, statement.acct_id),
         {:ok, statuses} <- import_transactions(scope, statement, account),
         :ok <- put_bank_balance(scope, account, statement.ledger_balance) do
      {:ok, statuses}
    end
  end

  defp import_transactions(scope, statement, account) do
    rows = Enum.filter(preview(scope, statement, account).rows, &(&1.status in [:new, :matched]))
    collect(rows, &create(scope, account, &1))
  end

  defp create(scope, account, %{transaction: transaction, status: status, match: match}) do
    attrs = %{
      account_id: account.id,
      date: transaction.date,
      amount: transaction.amount,
      payee_name: transaction.name,
      memo: transaction.memo,
      cleared: :cleared,
      source: :file,
      matched_transaction_id: match && match.id
    }

    with {:ok, created} <- Ledger.create_transaction(scope, attrs),
         {:ok, _origin} <- Ledger.add_origin(scope, created, :file, transaction.fitid) do
      {:ok, status}
    else
      {:error, changeset} -> {:error, {transaction, changeset}}
    end
  end

  defp put_bank_balance(_scope, _account, nil), do: :ok

  defp put_bank_balance(scope, account, balance) do
    with {:ok, _balance} <-
           Ledger.put_bank_balance(scope, account, Map.put(balance, :source, :file)),
         do: :ok
  end

  defp collect(items, fun) do
    items
    |> Enum.reduce_while({:ok, []}, fn item, {:ok, done} ->
      case fun.(item) do
        {:ok, result} -> {:cont, {:ok, [result | done]}}
        error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, done} -> {:ok, Enum.reverse(done)}
      error -> error
    end
  end
end
