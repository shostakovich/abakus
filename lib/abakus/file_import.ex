defmodule Abakus.FileImport do
  @moduledoc """
  The file import: the statements of an OFX/QFX file (`Abakus.FileImport.OFX`) into accounts. An account remembers
  the file's account (`BANKID`, `ACCTID`) once a statement went into it, so the next file finds it.

  Transactions come in through the import core (`Abakus.Import`) from source `file`, with their FITID as external id,
  the payee from `NAME` and the memo from `MEMO`. The statement's ledger balance becomes the account's bank balance
  from the file.

  Accounts fed by another app and closed ones take no file import. Everything goes through the Ledger with the
  caller's scope.
  """

  alias Abakus.FileImport.OFX
  alias Abakus.{Import, Ledger, Repo}
  alias Abakus.Ledger.Account
  alias Abakus.Users.Scope

  @doc "The statements of a file, or why it cannot be read."
  defdelegate read(content), to: OFX, as: :parse

  @doc "The accounts a statement can go into, in their order."
  def accounts(%Scope{} = scope), do: Import.accounts(scope)

  @doc "The account the statement's account is linked to, as long as it takes a file import."
  def linked_account(%Scope{} = scope, %{bank_id: bank_id, acct_id: acct_id}) do
    account = Ledger.get_account_by_ofx(scope, bank_id, acct_id)
    if account && Account.takes_entries?(account), do: account
  end

  @doc """
  The statement's transactions, each with its status in the account and how many have which, see
  `Abakus.Import.rows/4`.
  """
  def preview(%Scope{} = scope, statement, account) do
    rows = Import.rows(scope, account, :file, entries(statement))
    counts = Enum.frequencies_by(rows, & &1.status)

    Map.new([:new, :existing, :matched, :reconciled], &{&1, Map.get(counts, &1, 0)})
    |> Map.put(:rows, rows)
  end

  defp entries(statement), do: Enum.map(statement.transactions, &entry/1)

  defp entry(transaction),
    do: Map.merge(transaction, %{external_id: transaction.fitid, payee_name: transaction.name})

  @doc """
  Imports `{statement, account}` pairs, all or none: the new transactions and the match proposals, which wait for
  "Zuordnen" or "Trennen". Returns how many came in as `%{new, matched}`. Refuses an account that takes no file
  import or two statements into one account with a message, a transaction the Ledger refuses with
  `{transaction, changeset}`.
  """
  def import(%Scope{} = scope, statements) do
    Repo.transact(fn ->
      with {:ok, statements} <- fresh_accounts(scope, statements),
           {:ok, counts} <- Import.collect(statements, &import_statement(scope, &1)) do
        {:ok, Enum.reduce(counts, %{new: 0, matched: 0}, &add_counts/2)}
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

  defp add_counts(counts, sum), do: Map.merge(sum, counts, fn _key, a, b -> a + b end)

  defp import_statement(scope, {statement, account}) do
    with {:ok, account} <-
           Ledger.link_ofx_account(scope, account, statement.bank_id, statement.acct_id),
         {:ok, counts} <- Import.import(scope, account, :file, entries(statement)),
         :ok <- Import.put_bank_balance(scope, account, :file, statement.ledger_balance) do
      {:ok, counts}
    end
  end
end
