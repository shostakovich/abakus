defmodule Abakus.Depot.PortfoliosFixtures do
  @moduledoc "Portfolios, accounts and transactions for tests."

  alias Abakus.Depot.Portfolios.{Account, Portfolio, Transaction}
  alias Abakus.Repo
  alias Abakus.Users.Scope

  def portfolio_fixture(%Scope{user: user}, attrs \\ %{}),
    do: Repo.insert!(struct!(%Portfolio{user_id: user.id, name: "Langfristig"}, attrs))

  def account_fixture(%Scope{user: user}, attrs \\ %{}),
    do: Repo.insert!(struct!(%Account{user_id: user.id, name: "Konto", currency: "EUR"}, attrs))

  @doc "A transaction on `date`, at noon; `attrs` needs at least `type`."
  def transaction_fixture(%Scope{user: user}, date, attrs) do
    Repo.insert!(
      struct!(
        %Transaction{
          user_id: user.id,
          date_time: NaiveDateTime.new!(date, ~T[12:00:00]),
          amount: 0,
          currency: "EUR",
          source: :manual
        },
        attrs
      )
    )
  end

  @doc "Shares as stored, × 10⁸."
  def shares(count), do: round(count * 100_000_000)

  @doc "An amount as stored, in cents of its currency."
  def money(value), do: round(value * 100)
end
