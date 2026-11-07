defmodule Abakus.Bookkeeping.VatReturns do
  @moduledoc """
  The user's VAT returns (`Abakus.Bookkeeping.VatReturn`), computed from their tax lines on any of their accounts.
  The owner is taxed on receipts (Ist-Versteuerung), so a tax line counts on its transaction's date, output and
  input VAT alike; a part of a split counts with its own amount.
  """

  import Ecto.Query
  import Abakus.Owned

  alias Abakus.{Bookkeeping, Ledger, Repo}
  alias Abakus.Bookkeeping.{Category, TaxLine, VatReturn}
  alias Abakus.Users.Scope

  @doc "The Voranmeldung of `quarter` (1 to 4) of `year`."
  def quarter(%Scope{} = scope, year, quarter) do
    {first, last} = VatReturn.quarter_span(year, quarter)
    VatReturn.quarter(year, quarter, entries(scope, first, last))
  end

  @doc "The Umsatzsteuererklärung of `year`."
  def year(%Scope{} = scope, year),
    do: VatReturn.year(year, entries(scope, Date.new!(year, 1, 1), Date.new!(year, 12, 31)))

  defp entries(scope, first, last) do
    transactions =
      Repo.all(
        from t in Ledger.in_register(scope),
          where: t.date >= ^first and t.date <= ^last,
          where: t.id in subquery(from l in owned(TaxLine, scope), select: l.transaction_id),
          preload: :subtransactions
      )

    by_id = Map.new(transactions, &{&1.id, &1})

    for {{id, side}, line} <- Bookkeeping.tax_lines(scope, transactions),
        category = Category.get(line.category),
        category != nil do
      transaction = by_id[id]

      %{
        date: transaction.date,
        category: category,
        vat: line.vat,
        amount: amount(transaction, side)
      }
    end
  end

  defp amount(transaction, nil), do: transaction.amount

  defp amount(transaction, part_id),
    do: Enum.find_value(transaction.subtransactions, &(&1.id == part_id && &1.amount))
end
