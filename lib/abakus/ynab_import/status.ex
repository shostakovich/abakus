defmodule Abakus.YnabImport.Status do
  @moduledoc """
  What the last YNAB import brought over and when, read from the data; nothing is stored for it. The import writes
  its transactions last, each with its YNAB id as an origin, so the newest of those origins dates it, and what was
  created up to then came with it: a re-import replaces the whole budget (docs/adr/0002-ynab-reimport-replaces.md),
  so nothing older is left. Only the import adds YNAB origins; a counterpart created later copies the transaction's
  source, so the transactions' source would not do.
  """

  import Ecto.Query

  alias Abakus.Categories.{Assignment, Category, CategoryGroup}
  alias Abakus.Ledger.{Account, Payee, TransactionOrigin}
  alias Abakus.Repo

  defstruct [
    :imported_at,
    :accounts,
    :category_groups,
    :categories,
    :payees,
    :transactions,
    :first_month
  ]

  @doc "The status, or nil when nothing came from YNAB."
  def read do
    case Repo.one(
           from o in TransactionOrigin,
             where: o.source == :ynab,
             select: {max(o.inserted_at), count()}
         ) do
      {nil, 0} -> nil
      {imported_at, transactions} -> read(imported_at, transactions)
    end
  end

  defp read(imported_at, transactions) do
    %__MODULE__{
      imported_at: imported_at,
      transactions: transactions,
      accounts: count(Account, imported_at),
      category_groups: count(from(g in CategoryGroup, where: not g.internal), imported_at),
      categories: count(from(c in Category, where: not c.internal), imported_at),
      payees: count(from(p in Payee, where: is_nil(p.transfer_account_id)), imported_at),
      first_month: Repo.one(from a in created_by(Assignment, imported_at), select: min(a.month))
    }
  end

  defp count(queryable, imported_at),
    do: queryable |> created_by(imported_at) |> Repo.aggregate(:count)

  defp created_by(queryable, imported_at),
    do: where(queryable, [record], record.inserted_at <= ^imported_at)
end
