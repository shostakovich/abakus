defmodule Abakus.YnabImport.Status do
  @moduledoc """
  What the last YNAB import brought over and when, read from the data; nothing is stored for it. The import writes
  its transactions last, each with its YNAB id as an origin, so the newest of those origins dates it, and what was
  created up to then came with it: a re-import replaces the whole budget (DECISIONS.md, ADR 0002),
  so nothing older is left. Only the import adds YNAB origins; a counterpart created later copies the transaction's
  source, so the transactions' source would not do.
  """

  import Ecto.Query

  alias Abakus.Categories.{Assignment, Category, CategoryGroup}
  alias Abakus.Ledger.{Account, Payee, TransactionOrigin}
  alias Abakus.Repo
  alias Abakus.Users.{Scope, User}

  defstruct [
    :imported_at,
    :accounts,
    :category_groups,
    :categories,
    :payees,
    :transactions,
    :first_month
  ]

  @doc "The status of the user's budget, or nil when nothing came from YNAB."
  def read(%Scope{user: %User{id: user_id}}) do
    case Repo.one(
           from o in TransactionOrigin,
             where: o.user_id == ^user_id and o.source == :ynab,
             select: {max(o.inserted_at), count()}
         ) do
      {nil, 0} -> nil
      {imported_at, transactions} -> read(user_id, imported_at, transactions)
    end
  end

  defp read(user_id, imported_at, transactions) do
    created = &created_by(&1, user_id, imported_at)

    %__MODULE__{
      imported_at: imported_at,
      transactions: transactions,
      accounts: count(created.(Account)),
      category_groups: count(where(created.(CategoryGroup), [g], not g.internal)),
      categories: count(where(created.(Category), [c], not c.internal)),
      payees: count(where(created.(Payee), [p], is_nil(p.transfer_account_id))),
      first_month: Repo.one(from a in created.(Assignment), select: min(a.month))
    }
  end

  defp count(queryable), do: Repo.aggregate(queryable, :count)

  defp created_by(queryable, user_id, imported_at),
    do:
      where(
        queryable,
        [record],
        record.user_id == ^user_id and record.inserted_at <= ^imported_at
      )
end
