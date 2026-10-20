defmodule Abakus.Import do
  @moduledoc """
  The core the file import (`Abakus.FileImport`) and bank sync share, keyed by source (`:file`, `:bank`): which of
  an account's entries come in, how, and the bank balance.

  An entry is a map with `external_id`, `date`, `amount`, `payee_name` and `memo`; other keys stay as they are. An
  external id the account has from the source already (deleted transactions included) is not imported again, nor one
  that the entries repeat, nor an entry dated up to the account's newest reconciled transaction. One that looks like
  a transaction in the register comes in as a match proposal for it, never merged silently. Imports land unapproved
  and cleared; the payee comes from `payee_name` (the regular payee with its lookup key, else a new one), the memo
  from `memo`. Everything goes through the Ledger with the caller's scope.
  """

  alias Abakus.{Ledger, Repo}
  alias Abakus.Ledger.Account
  alias Abakus.Users.Scope

  @doc "The accounts entries can come into, in their order: open and fed by no other area."
  def accounts(%Scope{} = scope),
    do: Enum.filter(Ledger.list_accounts(scope), &Account.takes_entries?/1)

  @doc """
  The unique entries, each with its status in the account: `:existing` (its external id is there), `:reconciled`
  (dated up to the account's newest reconciled transaction, which takes no match, so it would come in twice),
  `:matched` (it proposes a match, see `Abakus.Ledger.find_matches/4`, for `match`) or `:new`. Without an account
  all are new.
  """
  def rows(%Scope{} = scope, account, source, entries),
    do: entries |> Enum.uniq_by(& &1.external_id) |> rows_in(scope, account, source)

  defp rows_in(entries, _scope, nil, _source), do: Enum.map(entries, &row(&1, :new))

  defp rows_in(entries, scope, account, source) do
    existing =
      Ledger.existing_external_ids(scope, account, source, Enum.map(entries, & &1.external_id))

    reconciled_until = Ledger.last_reconciled_date(scope, account)
    rows = Enum.map(entries, &row(&1, status(&1, existing, reconciled_until)))
    open = Enum.filter(rows, &(&1.status == :new))
    matches = Ledger.find_matches(scope, account, source, Enum.map(open, & &1.transaction))

    match_by_id =
      open
      |> Enum.zip(matches)
      |> Map.new(fn {row, match} -> {row.transaction.external_id, match} end)

    Enum.map(rows, fn row ->
      case match_by_id[row.transaction.external_id] do
        nil -> row
        match -> %{row | status: :matched, match: match}
      end
    end)
  end

  defp row(entry, status), do: %{transaction: entry, status: status, match: nil}

  defp status(entry, existing, reconciled_until) do
    cond do
      entry.external_id in existing -> :existing
      reconciled_until && Date.compare(entry.date, reconciled_until) != :gt -> :reconciled
      true -> :new
    end
  end

  @doc """
  Imports the account's new entries and match proposals, all or none, and returns how many came in as
  `%{new, matched}`; refuses an entry the Ledger refuses with `{entry, changeset}`.
  """
  def import(%Scope{} = scope, %Account{} = account, source, entries) do
    Repo.transact(fn ->
      rows =
        scope |> rows(account, source, entries) |> Enum.filter(&(&1.status in [:new, :matched]))

      with {:ok, statuses} <- collect(rows, &create(scope, account, source, &1)) do
        counts = Enum.frequencies(statuses)
        {:ok, %{new: Map.get(counts, :new, 0), matched: Map.get(counts, :matched, 0)}}
      end
    end)
  end

  defp create(scope, account, source, %{transaction: entry, status: status, match: match}) do
    attrs = %{
      account_id: account.id,
      date: entry.date,
      amount: entry.amount,
      payee_name: entry.payee_name,
      memo: entry.memo,
      cleared: :cleared,
      source: source,
      matched_transaction_id: match && match.id
    }

    with {:ok, created} <- Ledger.create_transaction(scope, attrs),
         {:ok, _origin} <- Ledger.add_origin(scope, created, source, entry.external_id) do
      {:ok, status}
    else
      {:error, changeset} -> {:error, {entry, changeset}}
    end
  end

  @doc "Keeps `%{date, amount}` as the account's bank balance from the source, one per date; nil keeps nothing."
  def put_bank_balance(%Scope{}, %Account{}, _source, nil), do: :ok

  def put_bank_balance(%Scope{} = scope, %Account{} = account, source, balance) do
    with {:ok, _balance} <-
           Ledger.put_bank_balance(scope, account, Map.put(balance, :source, source)),
         do: :ok
  end

  @doc "The results of `fun` for each item, in order, until it refuses one with anything but `{:ok, result}`."
  def collect(items, fun) do
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
