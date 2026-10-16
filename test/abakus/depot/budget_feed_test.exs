defmodule Abakus.Depot.BudgetFeedTest do
  use Abakus.DataCase

  import Abakus.Depot.{PortfoliosFixtures, SecuritiesFixtures}
  import Abakus.UsersFixtures
  import ExUnit.CaptureLog

  alias Abakus.Depot.{BudgetFeed, FakePriceFeed}
  alias Abakus.Depot.MarketData.Job
  alias Abakus.{DomainFixtures, Ledger, LocalTime}
  alias Abakus.Ledger.Transaction
  alias Abakus.Users.User

  @day ~D[2026-10-16]

  setup do
    owner = user_scope_fixture()
    portfolio = portfolio_fixture(owner, %{name: "Langfristig"})
    cash = account_fixture(owner, %{name: "Verrechnung"})
    depot = DomainFixtures.account_fixture(name: "Depot", kind: :tracking)
    %{owner: owner, portfolio: portfolio, cash: cash, depot: depot}
  end

  # 100 shares in the portfolio and 10.812,34 € on the cash account.
  defp holdings_fixture(c, security) do
    transaction_fixture(c.owner, ~D[2026-10-01],
      type: :inbound_delivery,
      portfolio_id: c.portfolio.id,
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

  defp balance_fixture(account, amount) do
    DomainFixtures.transaction_fixture(
      account_id: account.id,
      date: ~D[2026-10-01],
      amount: amount,
      cleared: :cleared
    )
  end

  defp feed(c, feeds), do: {:ok, _feeds} = BudgetFeed.put_feeds(c.owner, feeds)

  defp feed_both(c),
    do:
      feed(c, %{{:portfolio, c.portfolio.id} => c.depot.id, {:account, c.cash.id} => c.depot.id})

  defp value_changes(account) do
    Repo.all(
      from t in Transaction,
        where: t.account_id == ^account.id and t.source == :depot and is_nil(t.deleted_at),
        preload: :payee,
        order_by: t.id
    )
  end

  describe "the daily value change" do
    test "after the daily price fetch books the difference to the account's balance", c do
      security = security_fixture(%{symbol: "VGWL.DE"})
      holdings_fixture(c, security)
      balance_fixture(c.depot, 5_000_000)
      feed_both(c)
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

      assert [change] = value_changes(c.depot)

      assert {change.date, change.amount, change.payee.name, change.cleared, change.approved} ==
               {today, 81_234, "Wertänderung", :cleared, true}

      assert Ledger.balances()[c.depot.id].balance == 5_081_234

      Job.run()

      assert [^change] = value_changes(c.depot)
    end

    test "books a loss as an outflow, dated the given day", c do
      security = security_fixture(%{quote_feed: :manual, symbol: nil})
      price_fixture(security, ~D[2026-10-15], price(390), :manual)
      holdings_fixture(c, security)
      balance_fixture(c.depot, 5_000_000)
      feed_both(c)

      :ok = BudgetFeed.book_value_changes(@day)

      assert [%Transaction{date: @day, amount: -18_766}] = value_changes(c.depot)
    end

    test "a second run on the same day amends that day's value change", c do
      security = security_fixture(%{quote_feed: :manual, symbol: nil})
      price_fixture(security, ~D[2026-10-15], price(400), :manual)
      holdings_fixture(c, security)
      balance_fixture(c.depot, 5_000_000)
      feed_both(c)

      BudgetFeed.book_value_changes(@day)
      assert [%Transaction{amount: 81_234} = change] = value_changes(c.depot)

      price_fixture(security, @day, price(410), :manual)
      BudgetFeed.book_value_changes(@day)

      assert [%Transaction{id: id, date: @day, amount: 181_234}] = value_changes(c.depot)
      assert id == change.id
      assert Ledger.balances()[c.depot.id].balance == 5_181_234
    end

    test "a second run on the same day deletes a value change that comes to nothing", c do
      security = security_fixture(%{quote_feed: :manual, symbol: nil})
      price_fixture(security, ~D[2026-10-15], price(400), :manual)
      holdings_fixture(c, security)
      balance_fixture(c.depot, 5_000_000)
      feed_both(c)

      BudgetFeed.book_value_changes(@day)
      assert [%Transaction{amount: 81_234} = change] = value_changes(c.depot)

      balance_fixture(c.depot, 81_234)
      BudgetFeed.book_value_changes(@day)

      assert value_changes(c.depot) == []
      assert Repo.reload!(change).deleted_at
      assert Ledger.balances()[c.depot.id].balance == 5_081_234
    end

    test "leaves out transactions dated after the day", c do
      security = security_fixture(%{quote_feed: :manual, symbol: nil})
      price_fixture(security, ~D[2026-10-15], price(400), :manual)
      holdings_fixture(c, security)
      balance_fixture(c.depot, 5_000_000)

      DomainFixtures.transaction_fixture(
        account_id: c.depot.id,
        date: Date.add(@day, 1),
        amount: 70_000,
        cleared: :cleared
      )

      feed_both(c)

      BudgetFeed.book_value_changes(@day)

      assert [%Transaction{date: @day, amount: 81_234}] = value_changes(c.depot)
    end

    test "counts only what feeds the account", c do
      security = security_fixture(%{quote_feed: :manual, symbol: nil})
      price_fixture(security, ~D[2026-10-15], price(400), :manual)
      holdings_fixture(c, security)
      feed(c, %{{:account, c.cash.id} => c.depot.id})

      BudgetFeed.book_value_changes(@day)

      assert [%Transaction{amount: 1_081_234}] = value_changes(c.depot)
    end

    test "feeds each account from its own portfolios and accounts", c do
      security = security_fixture(%{quote_feed: :manual, symbol: nil})
      price_fixture(security, ~D[2026-10-15], price(400), :manual)
      holdings_fixture(c, security)
      other = DomainFixtures.account_fixture(name: "Tagesgeld", kind: :tracking)
      feed(c, %{{:portfolio, c.portfolio.id} => c.depot.id, {:account, c.cash.id} => other.id})

      BudgetFeed.book_value_changes(@day)

      assert [%Transaction{amount: 4_000_000}] = value_changes(c.depot)
      assert [%Transaction{amount: 1_081_234}] = value_changes(other)
    end

    test "leaves out closed accounts and does nothing without feeds", c do
      security = security_fixture(%{quote_feed: :manual, symbol: nil})
      price_fixture(security, ~D[2026-10-15], price(400), :manual)
      holdings_fixture(c, security)

      BudgetFeed.book_value_changes(@day)
      assert value_changes(c.depot) == []

      feed_both(c)
      {:ok, _closed} = Ledger.update_account(Repo.reload!(c.depot), %{closed: true})

      BudgetFeed.book_value_changes(@day)
      assert value_changes(c.depot) == []
    end

    test "books nothing once the user of the portfolios no longer owns the budget", c do
      balance_fixture(c.depot, 5_000)
      feed_both(c)

      transaction_fixture(c.owner, ~D[2026-10-01],
        type: :deposit,
        account_id: c.cash.id,
        amount: 100
      )

      other = user_scope_fixture()
      Repo.update_all(User, set: [budget_owner: false])
      Repo.update_all(where(User, id: ^other.user.id), set: [budget_owner: true])

      BudgetFeed.book_value_changes(@day)

      assert value_changes(c.depot) == []
    end

    test "logs a refused booking and books the other accounts", c do
      huge = account_fixture(c.owner, %{name: "Riesig"})

      transaction_fixture(c.owner, ~D[2026-10-01],
        type: :deposit,
        account_id: huge.id,
        amount: 10_000_000_000_001
      )

      transaction_fixture(c.owner, ~D[2026-10-01],
        type: :deposit,
        account_id: c.cash.id,
        amount: 100
      )

      other = DomainFixtures.account_fixture(name: "Tagesgeld", kind: :tracking)
      feed(c, %{{:account, huge.id} => other.id, {:account, c.cash.id} => c.depot.id})

      assert capture_log(fn -> BudgetFeed.book_value_changes(@day) end) =~
               "The value change of account #{other.id} was refused"

      assert value_changes(other) == []
      assert [%Transaction{amount: 100}] = value_changes(c.depot)
    end
  end

  describe "put_feeds/2" do
    test "makes an account fed by something fed by portfolio, and one fed by nothing manual again",
         c do
      other = DomainFixtures.account_fixture(name: "Tagesgeld", kind: :tracking)

      assert {:ok, feeds} =
               BudgetFeed.put_feeds(c.owner, %{
                 {:portfolio, "#{c.portfolio.id}"} => "#{c.depot.id}",
                 {:account, c.cash.id} => other.id
               })

      assert feeds == %{
               {:portfolio, c.portfolio.id} => c.depot.id,
               {:account, c.cash.id} => other.id
             }

      assert {Repo.reload!(c.depot).fed_by, Repo.reload!(other).fed_by} ==
               {:portfolio, :portfolio}

      assert {:ok, feeds} = BudgetFeed.put_feeds(c.owner, %{{:account, c.cash.id} => ""})

      assert feeds == %{{:portfolio, c.portfolio.id} => c.depot.id}
      assert {Repo.reload!(c.depot).fed_by, Repo.reload!(other).fed_by} == {:portfolio, nil}
    end

    test "moves a portfolio from one account to another", c do
      other = DomainFixtures.account_fixture(name: "Tagesgeld", kind: :tracking)
      feed(c, %{{:portfolio, c.portfolio.id} => c.depot.id})

      feed(c, %{{:portfolio, c.portfolio.id} => other.id})

      assert BudgetFeed.feeds(c.owner) == %{{:portfolio, c.portfolio.id} => other.id}
      assert {Repo.reload!(c.depot).fed_by, Repo.reload!(other).fed_by} == {nil, :portfolio}
    end

    test "offers open tracking accounts not fed by the Kasse", c do
      DomainFixtures.account_fixture(name: "Giro", kind: :checking)
      DomainFixtures.account_fixture(name: "Alt", kind: :tracking, closed: true)
      DomainFixtures.account_fixture(name: "Geteilt", kind: :tracking, fed_by: :shared_expenses)
      fed = DomainFixtures.account_fixture(name: "Depot 2", kind: :tracking, fed_by: :portfolio)

      assert Enum.map(BudgetFeed.account_choices(), & &1.id) == [c.depot.id, fed.id]
    end

    test "refuses accounts it does not offer", c do
      giro = DomainFixtures.account_fixture(name: "Giro", kind: :checking)

      assert BudgetFeed.put_feeds(c.owner, %{{:portfolio, c.portfolio.id} => giro.id}) ==
               {:error, :unknown}

      assert BudgetFeed.put_feeds(c.owner, %{{:portfolio, c.portfolio.id} => "x"}) ==
               {:error, :unknown}

      assert BudgetFeed.feeds(c.owner) == %{}
      assert Repo.reload!(giro).fed_by == nil
    end

    test "keeps a feed into an account closed since, but starts none there", c do
      feed(c, %{{:portfolio, c.portfolio.id} => c.depot.id})
      {:ok, depot} = Ledger.update_account(c.depot, %{closed: true})

      assert [%{id: id}] = BudgetFeed.fed_accounts_not_offered(BudgetFeed.feeds(c.owner))
      assert id == depot.id

      assert BudgetFeed.put_feeds(c.owner, %{
               {:portfolio, c.portfolio.id} => depot.id,
               {:account, c.cash.id} => depot.id
             }) == {:error, :unknown}

      assert {:ok, feeds} =
               BudgetFeed.put_feeds(c.owner, %{
                 {:portfolio, c.portfolio.id} => to_string(depot.id),
                 {:account, c.cash.id} => ""
               })

      assert feeds == %{{:portfolio, c.portfolio.id} => depot.id}
      assert Repo.reload!(depot).fed_by == :portfolio
    end

    test "refuses another user's portfolios and accounts", c do
      other = user_scope_fixture()
      portfolio = portfolio_fixture(other)
      cash = account_fixture(other)

      for item <- [{:portfolio, portfolio.id}, {:account, cash.id}, {:security, c.portfolio.id}] do
        assert BudgetFeed.put_feeds(c.owner, %{item => c.depot.id}) == {:error, :unknown}
      end

      assert BudgetFeed.feeds(c.owner) == %{}
    end

    test "is the budget owner's alone", c do
      other = user_scope_fixture()
      portfolio = portfolio_fixture(other)

      assert BudgetFeed.put_feeds(other, %{{:portfolio, portfolio.id} => c.depot.id}) ==
               {:error, :not_budget_owner}

      assert Repo.reload!(c.depot).fed_by == nil
    end
  end
end
