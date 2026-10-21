defmodule Abakus.Depot.PortfoliosFixtures do
  @moduledoc "Portfolios, their accounts in the Ledger and transactions for tests."

  alias Abakus.Depot.CashSide
  alias Abakus.Depot.Portfolios.{Portfolio, Transaction}
  alias Abakus.{Ledger, Repo}
  alias Abakus.Users.Scope

  def portfolio_fixture(%Scope{user: user}, attrs \\ %{}),
    do: Repo.insert!(struct!(%Portfolio{user_id: user.id, name: "Langfristig"}, attrs))

  @doc "A tracking account in the Ledger, unless `attrs` say otherwise."
  def account_fixture(%Scope{} = scope, attrs \\ %{}) do
    {:ok, account} =
      Ledger.create_account(scope, Enum.into(attrs, %{name: "Konto", kind: :tracking}))

    account
  end

  @doc "Makes `account` the cash of `portfolio`."
  def cash_account_fixture(%Portfolio{id: portfolio_id}, account) do
    Repo.insert_all("depot_cash_accounts", [%{portfolio_id: portfolio_id, account_id: account.id}])

    account
  end

  @doc "A transaction on `date`, at noon, with its cash side in the Ledger; `attrs` needs at least `type`."
  def transaction_fixture(%Scope{user: user} = scope, date, attrs) do
    transaction =
      Repo.insert!(
        struct!(
          %Transaction{
            user_id: user.id,
            date_time: NaiveDateTime.new!(date, ~T[12:00:00]),
            amount: 0,
            source: :manual
          },
          attrs
        )
      )

    :ok = CashSide.sync(scope)
    transaction
  end

  @doc "Shares as stored, × 10⁸."
  def shares(count), do: round(count * 100_000_000)

  @doc "An amount as stored, in euro cents."
  def money(value), do: round(value * 100)
end
