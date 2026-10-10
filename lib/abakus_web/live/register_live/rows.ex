defmodule AbakusWeb.RegisterLive.Rows do
  @moduledoc """
  Which transactions the register shows and what it shows beside them: the view (all, waiting for approval, not
  cleared), the search, the running balance and whether a transaction takes a category. Transactions come from
  `Abakus.Ledger.list_transactions/1`, newest first, with payee, category and subtransactions.
  """

  alias Abakus.Categories.Category
  alias Abakus.Ledger.{Account, Payee}
  alias Abakus.Names
  alias AbakusWeb.Format

  @filters [:all, :unapproved, :uncleared]

  def filters, do: @filters

  def filter(transactions, :all), do: transactions
  def filter(transactions, :unapproved), do: Enum.reject(transactions, & &1.approved)
  def filter(transactions, :uncleared), do: Enum.filter(transactions, &(&1.cleared == :uncleared))

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

  defp matches?(transaction, key) do
    sides = [transaction | transaction.subtransactions]

    texts =
      [Format.amount(abs(transaction.amount)) | Enum.flat_map(sides, &texts/1)]
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

  @doc "The balance after each transaction by id, going back from the working balance; newest first."
  def running(transactions, working) do
    {after_each, _before} =
      Enum.map_reduce(transactions, working, fn transaction, balance ->
        {{transaction.id, balance}, balance - transaction.amount}
      end)

    Map.new(after_each)
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

  defp transfer_account(%Payee{transfer_account_id: id}, accounts) when not is_nil(id),
    do: accounts[id]

  defp transfer_account(_payee, _accounts), do: nil
end
