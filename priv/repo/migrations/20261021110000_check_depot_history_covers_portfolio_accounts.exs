defmodule Abakus.Repo.Migrations.CheckDepotHistoryCoversPortfolioAccounts do
  use Ecto.Migration

  # Runs before the migrations that remove the portfolio accounts, so a refusal leaves the old schema to the old image.
  def up do
    short =
      for [id, name, first, portfolio, depot_first] <- rows(),
          depot_first == nil or depot_first > first,
          do:
            ~s|"#{name}" (account #{id}, #{portfolio}) from #{first}, the Depot #{since(depot_first)}|

    if short != [],
      do:
        raise(
          "The Depot's history does not reach back as far as these portfolio accounts': " <>
            Enum.join(short, "; ") <>
            ". Nothing was changed. Run the previous version, book these portfolios' earlier transactions " <>
            "in the Depot, then update again, or Vermögen loses those days."
        )
  end

  def down, do: :ok

  defp rows do
    repo().query!(
      """
      SELECT a.id, a.name, min(t.date),
        coalesce('portfolio "' || p.name || '"', 'no portfolio, so the whole Depot'),
        CASE WHEN p.id IS NULL
          THEN (SELECT min(substr(d.date_time, 1, 10)) FROM depot_transactions d WHERE d.user_id = a.user_id)
          ELSE (SELECT min(substr(d.date_time, 1, 10)) FROM depot_transactions d
            WHERE d.user_id = p.user_id AND (d.portfolio_id = p.id OR d.other_portfolio_id = p.id
              OR d.account_id IN (SELECT c.id FROM depot_accounts c WHERE c.cash_of_portfolio_id = p.id)
              OR d.other_account_id IN (SELECT c.id FROM depot_accounts c WHERE c.cash_of_portfolio_id = p.id)))
        END
      FROM accounts a
      JOIN transactions t ON t.account_id = a.id AND t.deleted_at IS NULL AND t.matched_transaction_id IS NULL
      LEFT JOIN depot_portfolios p ON p.budget_account_id = a.id
      WHERE a.fed_by = 'portfolio'
      GROUP BY a.id ORDER BY a.id
      """,
      [],
      log: false
    ).rows
  end

  defp since(nil), do: "has no transactions"
  defp since(date), do: "from #{date}"
end
