defmodule Abakus.Depot.CashSideTest do
  use Abakus.DataCase

  import Abakus.Depot.{PortfoliosFixtures, SecuritiesFixtures}
  import Abakus.UsersFixtures

  alias Abakus.Depot.{AccountRoles, BudgetLink, CashSide, Portfolios, Valuation}
  alias Abakus.{DomainFixtures, Ledger}
  alias Abakus.Ledger.{Account, Transaction}

  @day ~D[2026-10-02]

  setup do
    anna = user_scope_fixture()
    checking = DomainFixtures.account_fixture(name: "Checking")

    {:ok, broker} =
      Portfolios.create_portfolio(anna, %{name: "Broker", account_name: "Broker cash"})

    %{
      anna: anna,
      checking: checking,
      broker: broker,
      broker_cash: Repo.get!(Portfolios.Account, broker.reference_account_id)
    }
  end

  defp ledger_account(depot_account),
    do: Repo.get!(Account, Repo.reload!(depot_account).ledger_account_id)

  defp register(account) do
    Repo.all(
      from t in Transaction,
        where: t.account_id == ^account.id and is_nil(t.deleted_at),
        order_by: t.id,
        preload: :payee
    )
  end

  defp budget_transactions(scope) do
    Repo.all(
      from t in Ledger.in_register(scope),
        join: a in assoc(t, :account),
        where: a.kind in ^Account.budget_kinds()
    )
  end

  defp deposit(c, account, amount, date \\ ~D[2026-09-30]) do
    transaction_fixture(c.anna, date, type: :deposit, account_id: account.id, amount: amount)
  end

  test "a purchase from broker cash is an outflow in its tracking account and leaves the budget alone",
       c do
    category = DomainFixtures.category_fixture(name: "Investing")

    {:ok, _link} =
      BudgetLink.switch_on(c.anna, %{category_id: category.id, start_date: ~D[2026-09-01]})

    deposit(c, c.broker_cash, 100_000)
    :ok = CashSide.sync(c.anna)
    budget_before = budget_transactions(c.anna)
    security = security_fixture(%{name: "World ETF", quote_feed: :manual, symbol: nil})

    {:ok, _transactions} =
      Portfolios.book_transaction(c.anna, Portfolios.transaction_choices(c.anna), %{
        "kind" => "purchase",
        "date" => Date.to_iso8601(@day),
        "portfolio_id" => c.broker.id,
        "security_id" => security.id,
        "account_id" => c.broker_cash.id,
        "shares" => "5",
        "price" => "100"
      })

    broker_cash = ledger_account(c.broker_cash)
    assert {broker_cash.name, broker_cash.kind} == {"Broker cash", :tracking}

    assert [_deposit, %Transaction{amount: -50_000, date: @day} = purchase] =
             register(broker_cash)

    assert {purchase.payee.name, purchase.memo, purchase.category_id} ==
             {"Broker", "Kauf World ETF", nil}

    assert {purchase.cleared, purchase.approved} == {:cleared, true}
    assert budget_transactions(c.anna) == budget_before
  end

  test "a tracking account holds the whole history, its balance the Depot's", c do
    security = security_fixture(%{name: "World ETF", quote_feed: :manual, symbol: nil})
    cash = c.broker_cash

    deposit(c, cash, 200_000, ~D[2020-01-02])

    for {type, amount, attrs} <- [
          {:buy, 120_000, [portfolio_id: c.broker.id, security_id: security.id, shares: 1]},
          {:dividend, 3_000, [security_id: security.id]},
          {:interest, 150, []},
          {:fee, 500, []},
          {:tax, 700, [security_id: security.id]},
          {:removal, 10_000, []}
        ] do
      transaction_fixture(
        c.anna,
        ~D[2021-06-01],
        [type: type, account_id: cash.id, amount: amount] ++ attrs
      )
    end

    :ok = CashSide.sync(c.anna)

    account = ledger_account(cash)
    depot = Valuation.balances(Portfolios.list_transactions(c.anna), @day)

    assert Ledger.balance(c.anna, account, @day) == depot[cash.id]
    assert Ledger.balance(c.anna, account, @day) == 71_950
    assert length(register(account)) == 7
    assert Enum.all?(register(account), &(&1.source == :depot and &1.depot_transaction_id))
  end

  test "a cash transfer between two Verrechnungskonten outside the budget is a transfer", c do
    other = account_fixture(c.anna, %{name: "Savings plan cash"})
    deposit(c, c.broker_cash, 50_000)

    transaction_fixture(c.anna, @day,
      type: :cash_transfer,
      account_id: c.broker_cash.id,
      other_account_id: other.id,
      amount: 20_000
    )

    :ok = CashSide.sync(c.anna)

    [_deposit, out] = register(ledger_account(c.broker_cash))
    assert [into] = register(ledger_account(other))

    assert {out.amount, into.amount, out.transfer_transaction_id} == {-20_000, 20_000, into.id}
    assert out.payee.transfer_account_id == ledger_account(other).id
    assert {into.cleared, into.approved} == {:cleared, true}
  end

  test "a cash transfer from a budget account is booked only on the tracking side before the link",
       c do
    clearing = account_fixture(c.anna, %{name: "Checking clearing"})
    {:ok, _} = AccountRoles.set_role(c.anna, clearing, "budget_account:#{c.checking.id}")

    transaction_fixture(c.anna, @day,
      type: :cash_transfer,
      account_id: clearing.id,
      other_account_id: c.broker_cash.id,
      amount: 30_000
    )

    :ok = CashSide.sync(c.anna)

    assert register(c.checking) == []

    assert [%Transaction{amount: 30_000, transfer_transaction_id: nil} = into] =
             register(ledger_account(c.broker_cash))

    assert into.payee.name == "Checking"
  end

  test "closes the accounts of retired Verrechnungskonten and of retired portfolios' cash", c do
    retired = portfolio_fixture(c.anna, %{name: "Old", retired: true})
    old_cash = account_fixture(c.anna, %{name: "Old cash", cash_of_portfolio_id: retired.id})
    unused = account_fixture(c.anna, %{name: "Unused", retired: true, no_role: true})
    loose = account_fixture(c.anna, %{name: "Loose", no_role: true})

    :ok = CashSide.sync(c.anna)

    for {depot_account, closed} <- [
          {old_cash, true},
          {unused, true},
          {loose, false},
          {c.broker_cash, false}
        ] do
      account = ledger_account(depot_account)

      assert {account.name, account.kind, account.closed} ==
               {depot_account.name, :tracking, closed}
    end
  end

  test "another user's Verrechnungskonten are tracking accounts of theirs", c do
    ben = user_scope_fixture()

    {:ok, portfolio} =
      Portfolios.create_portfolio(ben, %{name: "Ben's", account_name: "Ben's cash"})

    cash = Repo.get!(Portfolios.Account, portfolio.reference_account_id)
    deposit(%{anna: ben}, cash, 10_000)
    :ok = CashSide.sync(ben)

    account = ledger_account(cash)
    assert account.user_id == ben.user.id
    assert [%Transaction{amount: 10_000, user_id: user_id}] = register(account)
    assert user_id == ben.user.id
    assert Ledger.list_transactions(c.anna, :all) == []
  end
end
