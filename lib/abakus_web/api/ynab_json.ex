defmodule AbakusWeb.Api.YnabJSON do
  @moduledoc """
  Abakus as YNAB's API shows it: ids as strings, amounts in milliunits (cents × 10), tracking accounts as
  `otherAsset`. Nothing is ever deleted but transactions, so `deleted` is false elsewhere.
  """

  alias Abakus.Categories.{Category, CategoryGroup}
  alias Abakus.Ledger.{Account, Transaction}
  alias AbakusWeb.Api

  @currency_format %{
    iso_code: "EUR",
    example_format: "123.456,78",
    decimal_digits: 2,
    decimal_separator: ",",
    symbol_first: false,
    group_separator: ".",
    currency_symbol: "€",
    display_symbol: true
  }

  @doc "The one plan with its accounts; `balances` as from `Abakus.Ledger.balances/0`."
  def plan(accounts, balances) do
    %{
      id: Api.plan_id(),
      name: "Abakus",
      currency_format: @currency_format,
      accounts: Enum.map(accounts, &account(&1, balances))
    }
  end

  def account(%Account{} = account, balances) do
    balance = Map.get(balances, account.id, %{balance: 0, cleared: 0, uncleared: 0})

    %{
      id: id(account.id),
      name: account.name,
      type: account_type(account),
      on_budget: Account.budget_account?(account),
      closed: account.closed,
      note: account.note,
      balance: milliunits(balance.balance),
      cleared_balance: milliunits(balance.cleared),
      uncleared_balance: milliunits(balance.uncleared),
      deleted: false
    }
  end

  defp account_type(%Account{kind: :tracking}), do: "otherAsset"
  defp account_type(%Account{kind: kind}), do: Atom.to_string(kind)

  def category_group(%CategoryGroup{} = group) do
    %{
      id: id(group.id),
      name: group.name,
      hidden: false,
      internal: group.internal,
      deleted: false,
      categories: Enum.map(group.categories, &category/1)
    }
  end

  defp category(%Category{} = category) do
    %{
      id: id(category.id),
      category_group_id: id(category.category_group_id),
      name: category.name,
      hidden: false,
      internal: category.internal,
      note: category.note,
      deleted: false
    }
  end

  @doc "A transaction with its payee loaded."
  def transaction(%Transaction{} = transaction) do
    %{
      id: id(transaction.id),
      account_id: id(transaction.account_id),
      date: Date.to_iso8601(transaction.date),
      amount: milliunits(transaction.amount),
      payee_name: transaction.payee && transaction.payee.name,
      memo: transaction.memo,
      category_id: id(transaction.category_id),
      cleared: Atom.to_string(transaction.cleared),
      approved: transaction.approved,
      deleted: not is_nil(transaction.deleted_at)
    }
  end

  defp id(nil), do: nil
  defp id(id), do: Integer.to_string(id)

  defp milliunits(cents), do: cents * 10
end
