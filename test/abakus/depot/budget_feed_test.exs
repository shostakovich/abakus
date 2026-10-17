defmodule Abakus.Depot.BudgetFeedTest do
  use Abakus.DataCase

  import Abakus.DomainFixtures, only: [budget_scope: 0]
  import Abakus.Depot.{PortfoliosFixtures, SecuritiesFixtures}
  import Abakus.UsersFixtures
  import ExUnit.CaptureLog

  alias Abakus.Depot.{AccountRoles, BudgetFeed, FakePriceFeed, Portfolios}
  alias Abakus.Depot.MarketData.Job
  alias Abakus.Depot.Portfolios.Portfolio
  alias Abakus.{DomainFixtures, Ledger, LocalTime}
  alias Abakus.Ledger.{Account, Transaction}
  alias Abakus.Users.User

  @day ~D[2026-10-16]

  setup do
    owner = user_scope_fixture()
    portfolio = portfolio_fixture(owner, %{name: "Langfristig"})
    cash = account_fixture(owner, %{name: "Verrechnung"})
    %{owner: owner, portfolio: portfolio, cash: cash}
  end

  defp manual_security(price) do
    security = security_fixture(%{quote_feed: :manual, symbol: nil})
    price_fixture(security, ~D[2026-10-15], price(price), :manual)
    security
  end

  # 100 shares in the portfolio and 10.812,34 € on its Verrechnungskonto.
  defp holdings_fixture(c, security, portfolio \\ nil) do
    transaction_fixture(c.owner, ~D[2026-10-01],
      type: :inbound_delivery,
      portfolio_id: (portfolio || c.portfolio).id,
      security_id: security.id,
      shares: shares(100),
      amount: money(40_000)
    )

    transaction_fixture(c.owner, ~D[2026-10-01],
      type: :deposit,
      account_id: c.cash.id,
      amount: 1_081_234
    )
  end

  defp balance_fixture(account, amount, date \\ ~D[2026-10-01]) do
    DomainFixtures.transaction_fixture(
      account_id: account.id,
      date: date,
      amount: amount,
      cleared: :cleared
    )
  end

  defp account_of(portfolio) do
    %Portfolio{budget_account_id: id} = Repo.reload!(portfolio)
    id && Repo.get!(Account, id)
  end

  defp value_changes(account) do
    Repo.all(
      from t in Transaction,
        where: t.account_id == ^account.id and t.source == :depot and is_nil(t.deleted_at),
        preload: :payee,
        order_by: t.id
    )
  end

  defp balance(account), do: Ledger.balances(budget_scope())[account.id].balance

  describe "the switch to one account per portfolio" do
    test "closes the old fed account with its history and starts each portfolio's account at its value",
         c do
      security = manual_security(400)
      holdings_fixture(c, security)
      other = portfolio_fixture(c.owner, %{name: "Kinder"})
      holdings_fixture(c, security, other)
      old = DomainFixtures.account_fixture(name: "Depot", kind: :tracking, fed_by: :portfolio)
      history = balance_fixture(old, 5_000_000)

      :ok = BudgetFeed.book_value_changes(@day)

      assert %Account{closed: true} = Repo.reload!(old)
      assert Repo.reload!(history).deleted_at == nil
      assert [%Transaction{date: @day, amount: -5_000_000}] = value_changes(old)
      assert balance(old) == 0

      for portfolio <- [c.portfolio, other] do
        account = account_of(portfolio)

        assert {account.name, account.kind, account.fed_by, account.closed} ==
                 {portfolio.name, :tracking, :portfolio, false}

        assert [%Transaction{date: @day, amount: 4_000_000} = start] = value_changes(account)
        assert start.payee.name == "Wertänderung"
      end
    end

    test "opens the account of a portfolio of the budget owner as it is created, its new Verrechnungskonto its cash",
         c do
      {:ok, portfolio} =
        Portfolios.create_portfolio(c.owner, %{name: "Neu", account_name: "Neu-Verrechnung"})

      assert %Account{name: "Neu", kind: :tracking, fed_by: :portfolio} = account_of(portfolio)
      assert [cash_id] = AccountRoles.cash_account_ids(portfolio)
      assert cash_id == portfolio.reference_account_id

      member = user_scope_fixture()
      {:ok, theirs} = Portfolios.create_portfolio(member, %{name: "Ihr", account_name: "Konto"})

      assert account_of(theirs) == nil
    end

    test "gives no account to another user's portfolio", c do
      member = user_scope_fixture()
      theirs = portfolio_fixture(member, %{name: "Ihr"})

      :ok = BudgetFeed.sync_accounts()

      assert account_of(c.portfolio)
      assert account_of(theirs) == nil
    end

    test "renames an account after its renamed portfolio", c do
      :ok = BudgetFeed.sync_accounts()
      Repo.update!(change(c.portfolio, name: "Rente"))

      :ok = BudgetFeed.sync_accounts()

      assert account_of(c.portfolio).name == "Rente"
    end

    test "keeps the account's leading emoji when it renames it", c do
      :ok = BudgetFeed.sync_accounts()

      {:ok, _account} =
        Ledger.update_account(budget_scope(), account_of(c.portfolio), %{name: "📈 Alt"})

      Repo.update!(change(c.portfolio, name: "Rente"))

      :ok = BudgetFeed.sync_accounts()
      :ok = BudgetFeed.sync_accounts()

      assert account_of(c.portfolio).name == "📈 Rente"
    end

    test "opens no account for a retired portfolio", c do
      retired = portfolio_fixture(c.owner, %{name: "Alt", retired: true})

      :ok = BudgetFeed.sync_accounts()

      assert account_of(c.portfolio)
      assert account_of(retired) == nil
    end

    test "keeps an account the user closed closed and opens no other", c do
      :ok = BudgetFeed.sync_accounts()
      account = account_of(c.portfolio)
      {:ok, _closed} = Ledger.update_account(budget_scope(), account, %{closed: true})

      :ok = BudgetFeed.book_value_changes(@day)

      assert account_of(c.portfolio).id == account.id
      assert %Account{closed: true} = Repo.reload!(account)
      assert Repo.aggregate(Account, :count) == 1
    end

    test "keeps the Depot's value in the Vermögen history before the switch", c do
      holdings_fixture(c, manual_security(400))
      old = DomainFixtures.account_fixture(name: "Depot", kind: :tracking, fed_by: :portfolio)
      balance_fixture(old, 5_000_000)

      :ok = BudgetFeed.book_value_changes(@day)

      assert Ledger.net_worth(budget_scope(), Date.range(~D[2026-10-15], @day)) == [
               {~D[2026-10-15], 5_000_000},
               {@day, 4_000_000}
             ]

      assert Ledger.first_open_date(budget_scope()) == ~D[2026-10-01]
    end

    test "finds the portfolio of its account", c do
      :ok = BudgetFeed.sync_accounts()
      account = account_of(c.portfolio)

      assert BudgetFeed.portfolio(c.owner, account).id == c.portfolio.id
      assert BudgetFeed.portfolio(user_scope_fixture(), account) == nil
      assert BudgetFeed.portfolio(c.owner, DomainFixtures.account_fixture(name: "Giro")) == nil
    end
  end

  describe "the daily value change" do
    test "lands in the budget owner's budget with their user", c do
      holdings_fixture(c, manual_security(400))
      member = user_scope_fixture()

      :ok = BudgetFeed.book_value_changes(@day)

      assert [%Transaction{user_id: user_id, payee: payee}] =
               value_changes(account_of(c.portfolio))

      assert user_id == c.owner.user.id
      assert payee.user_id == c.owner.user.id
      assert Ledger.list_transactions(member, :all) == []
    end

    test "counts the balance of the portfolio's cash, and of no other Verrechnungskonto", c do
      holdings_fixture(c, manual_security(400))
      {:ok, _cash} = AccountRoles.set_role(c.owner, c.cash, "portfolio_cash:#{c.portfolio.id}")
      giro = account_fixture(c.owner, %{name: "Giro-Verrechnung"})

      transaction_fixture(c.owner, ~D[2026-10-01],
        type: :deposit,
        account_id: giro.id,
        amount: 50_000
      )

      {:ok, _giro} = AccountRoles.set_role(c.owner, giro, "none")

      :ok = BudgetFeed.book_value_changes(@day)

      assert [%Transaction{amount: 5_081_234}] = value_changes(account_of(c.portfolio))
    end

    test "after the daily price fetch books the difference to the account's balance", c do
      security = security_fixture(%{symbol: "VGWL.DE"})
      holdings_fixture(c, security)
      :ok = BudgetFeed.sync_accounts()
      account = account_of(c.portfolio)
      balance_fixture(account, 3_900_000)
      today = LocalTime.today()

      FakePriceFeed.stub(fn _symbol, _from, now ->
        {:ok,
         %{
           currency: "EUR",
           name: "Weltindex-ETF",
           closes: [{today, price(400)}],
           quote: %{at: now, date: today, close: price(400)}
         }}
      end)

      Job.run()

      assert [change] = value_changes(account)

      assert {change.date, change.amount, change.payee.name, change.cleared, change.approved} ==
               {today, 100_000, "Wertänderung", :cleared, true}

      assert balance(account) == 4_000_000

      Job.run()

      assert [^change] = value_changes(account)
    end

    test "books a loss as an outflow, dated the given day", c do
      holdings_fixture(c, manual_security(390))
      :ok = BudgetFeed.sync_accounts()
      account = account_of(c.portfolio)
      balance_fixture(account, 4_000_000)

      :ok = BudgetFeed.book_value_changes(@day)

      assert [%Transaction{date: @day, amount: -100_000}] = value_changes(account)
    end

    test "a second run on the same day amends that day's value change", c do
      security = manual_security(400)
      holdings_fixture(c, security)

      BudgetFeed.book_value_changes(@day)
      account = account_of(c.portfolio)
      assert [%Transaction{amount: 4_000_000} = change] = value_changes(account)

      price_fixture(security, @day, price(410), :manual)
      BudgetFeed.book_value_changes(@day)

      assert [%Transaction{id: id, date: @day, amount: 4_100_000}] = value_changes(account)
      assert id == change.id
      assert balance(account) == 4_100_000
    end

    test "a second run on the same day deletes a value change that comes to nothing", c do
      holdings_fixture(c, manual_security(400))

      BudgetFeed.book_value_changes(@day)
      account = account_of(c.portfolio)
      assert [%Transaction{amount: 4_000_000} = change] = value_changes(account)

      balance_fixture(account, 4_000_000)
      BudgetFeed.book_value_changes(@day)

      assert value_changes(account) == []
      assert Repo.reload!(change).deleted_at
      assert balance(account) == 4_000_000
    end

    test "leaves out transactions dated after the day", c do
      holdings_fixture(c, manual_security(400))
      :ok = BudgetFeed.sync_accounts()
      account = account_of(c.portfolio)
      balance_fixture(account, 70_000, Date.add(@day, 1))

      BudgetFeed.book_value_changes(@day)

      assert [%Transaction{date: @day, amount: 4_000_000}] = value_changes(account)
    end

    test "books nothing once the user of the portfolios no longer owns the budget", c do
      holdings_fixture(c, manual_security(400))
      :ok = BudgetFeed.sync_accounts()
      account = account_of(c.portfolio)

      other = user_scope_fixture()
      Repo.update_all(User, set: [budget_owner: false])
      Repo.update_all(where(User, id: ^other.user.id), set: [budget_owner: true])

      BudgetFeed.book_value_changes(@day)

      assert value_changes(account) == []
    end

    test "logs a refused booking and books the other accounts", c do
      huge = portfolio_fixture(c.owner, %{name: "Riesig"})
      security = manual_security(400)
      holdings_fixture(c, security)

      transaction_fixture(c.owner, ~D[2026-10-01],
        type: :inbound_delivery,
        portfolio_id: huge.id,
        security_id: security.id,
        shares: shares(1_000_000_000),
        amount: 0
      )

      :ok = BudgetFeed.sync_accounts()

      assert capture_log(fn -> BudgetFeed.book_value_changes(@day) end) =~
               "The value change of account #{account_of(huge).id} was refused"

      assert value_changes(account_of(huge)) == []
      assert [%Transaction{amount: 4_000_000}] = value_changes(account_of(c.portfolio))
    end
  end
end
