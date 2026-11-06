defmodule AbakusWeb.RegisterLive.Rows do
  @moduledoc """
  Which transactions the register shows and what it shows beside them: the view (all, waiting for approval, not
  cleared, without a category), the search and whether a transaction takes a category. Transactions come from
  `Abakus.Ledger.list_transactions/3` (match proposals from `list_match_proposals/2`), newest first, with payee,
  category and subtransactions.
  """

  alias Abakus.Categories.Category
  alias Abakus.Ledger.{Account, Payee}
  alias Abakus.Money
  alias Abakus.Names

  @filters [:all, :unapproved, :uncleared, :needs_category]

  def filters, do: @filters

  @doc "The match proposals a view shows; the Ledger narrows the transactions."
  def filter(proposals, :all), do: proposals
  def filter(proposals, :unapproved), do: Enum.reject(proposals, & &1.approved)
  def filter(proposals, :uncleared), do: Enum.filter(proposals, &(&1.cleared == :uncleared))
  # A proposal takes its category from the transaction it matches.
  def filter(_proposals, :needs_category), do: []

  @doc """
  The transactions whose payee, category, memo (a split's parts included) or amount ("48,75") contain the query,
  compared by lookup key, so emoji, case and "ß" against "ss" do not matter. Ready to Assign is found as "Zu
  verteilen".
  """
  def search(transactions, query) do
    case Names.lookup_key(query) do
      "" -> transactions
      key -> Enum.filter(transactions, &matches?(&1, key))
    end
  end

  @doc "Whether `search/2` narrows anything with the query."
  def searching?(query), do: Names.lookup_key(query) != ""

  defp matches?(transaction, key) do
    sides = [transaction | transaction.subtransactions]

    texts =
      [Money.amount(abs(transaction.amount)) | Enum.flat_map(sides, &texts/1)]
      |> Enum.reject(&is_nil/1)

    Enum.any?(texts, &String.contains?(&1, key))
  end

  defp texts(side), do: [payee_key(side.payee), category_key(side.category), memo_key(side.memo)]

  defp payee_key(%Payee{lookup_key: key}), do: key
  defp payee_key(_none), do: nil

  defp category_key(%Category{internal: true}), do: Names.lookup_key("Zu verteilen")
  defp category_key(%Category{lookup_key: key}), do: key
  defp category_key(_none), do: nil

  defp memo_key(memo) when is_binary(memo), do: Names.lookup_key(memo)
  defp memo_key(_none), do: nil

  @doc "Transactions and match proposals in one list, newest first, as the register shows them."
  def with_proposals(transactions, []), do: transactions

  def with_proposals(transactions, proposals),
    do: Enum.sort_by(transactions ++ proposals, &{Date.to_gregorian_days(&1.date), &1.id}, :desc)

  @doc "The transactions, newest first, with `{:month, first_day}` before each month's first one."
  def with_months(transactions) do
    transactions
    |> Enum.chunk_by(&Date.beginning_of_month(&1.date))
    |> Enum.flat_map(fn [first | _] = month ->
      [{:month, Date.beginning_of_month(first.date)} | month]
    end)
  end

  @doc """
  Whether a category can be set on the transaction itself: it is in a budget account, no split, and no transfer
  to another budget account (a transfer to a tracking account needs one). `accounts` maps ids to accounts.
  """
  def categorisable?(transaction, accounts) do
    transaction.subtransactions == [] and
      Account.takes_category?(
        accounts[transaction.account_id],
        transfer_account(transaction.payee, accounts)
      )
  end

  @doc """
  Whether the transaction, or with `transaction` the part of it, needs a category, as the view Ohne Kategorie
  (`Abakus.Ledger.list_transactions/3`) lists it: in a budget account, without one, not zero and no transfer to
  another budget account. A split needs one only in its parts.
  """
  def needs_category?(%{subtransactions: [_ | _]}, _accounts), do: false

  def needs_category?(transaction, accounts),
    do: missing_category?(transaction, accounts[transaction.account_id], accounts)

  def needs_category?(part, transaction, accounts),
    do: missing_category?(part, accounts[transaction.account_id], accounts)

  defp missing_category?(side, account, accounts) do
    is_nil(side.category_id) and side.amount != 0 and
      Account.takes_category?(account, transfer_account(side.payee, accounts))
  end

  defp transfer_account(%Payee{transfer_account_id: id}, accounts) when not is_nil(id),
    do: accounts[id]

  defp transfer_account(_payee, _accounts), do: nil
end
