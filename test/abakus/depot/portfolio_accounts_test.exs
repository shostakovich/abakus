defmodule Abakus.Depot.PortfolioAccountsTest do
  use Abakus.DataCase

  import Abakus.Depot.{PortfoliosFixtures, SecuritiesFixtures}
  import Abakus.UsersFixtures

  alias Abakus.Depot.Portfolios
  alias Abakus.Depot.Portfolios.Portfolio
  alias Abakus.Ledger
  alias Abakus.Ledger.Transaction, as: LedgerTransaction

  @friday ~D[2026-10-02]
  @saturday ~D[2026-10-03]

  setup do
    scope = user_scope_fixture()
    broker = account_fixture(scope, %{name: "Broker"})
    portfolio = portfolio_fixture(scope, %{name: "Langfristig", reference_account_id: broker.id})
    %{scope: scope, broker: broker, portfolio: portfolio}
  end

  defp ids(accounts), do: accounts |> Enum.map(& &1.id) |> Enum.sort()

  defp reference_id(portfolio), do: Repo.get!(Portfolio, portfolio.id).reference_account_id

  defp deposit(scope, account, amount) do
    transaction_fixture(scope, @friday,
      type: :deposit,
      account_id: account.id,
      amount: money(amount)
    )
  end

  test "cash_account_portfolios/1 gives the portfolio of each tracking account that is a Verrechnungskonto",
       ctx do
    old_cash = account_fixture(ctx.scope, %{name: "Alt-Cash", closed: true})
    retired = portfolio_fixture(ctx.scope, %{retired: true, reference_account_id: old_cash.id})
    giro = account_fixture(ctx.scope, %{name: "Giro", kind: :checking})
    portfolio_fixture(ctx.scope, %{name: "Giro-Depot", reference_account_id: giro.id})
    portfolio_fixture(ctx.scope, %{name: "Ohne Konto"})
    other = user_scope_fixture()
    portfolio_fixture(other, %{reference_account_id: account_fixture(other).id})

    assert Portfolios.cash_account_portfolios(ctx.scope) == %{
             ctx.broker.id => ctx.portfolio.id,
             old_cash.id => retired.id
           }
  end

  describe "account_choices/2" do
    test "offers the open accounts but the shared-expenses account and another portfolio's cash",
         ctx do
      giro = account_fixture(ctx.scope, %{name: "Giro", kind: :checking})
      portfolio_fixture(ctx.scope, %{name: "Teilt Giro", reference_account_id: giro.id})
      shared = account_fixture(ctx.scope, %{name: "Kasse", kind: :checking})
      {:ok, _shared} = Ledger.update_account(ctx.scope, shared, %{shared_expenses: true})
      account_fixture(ctx.scope, %{name: "Alt", closed: true})
      free = account_fixture(ctx.scope, %{name: "Frei"})
      taken = account_fixture(ctx.scope, %{name: "Vergeben"})
      portfolio_fixture(ctx.scope, %{name: "Anderes", reference_account_id: taken.id})
      account_fixture(user_scope_fixture(), %{name: "Fremd"})

      choices = Portfolios.account_choices(ctx.scope, ctx.portfolio)

      assert ids(choices.accounts) == ids([ctx.broker, giro, free])
      assert choices.owners == %{taken.id => "Anderes"}
    end

    test "counts a retired portfolio's cash as taken", ctx do
      old_cash = account_fixture(ctx.scope, %{name: "Alt-Cash"})

      portfolio_fixture(ctx.scope, %{
        name: "Alt",
        retired: true,
        reference_account_id: old_cash.id
      })

      choices = Portfolios.account_choices(ctx.scope, ctx.portfolio)

      refute old_cash.id in ids(choices.accounts)
      assert choices.owners == %{old_cash.id => "Alt"}
    end

    test "keeps the portfolio's own account though it is closed", ctx do
      {:ok, _closed} = Ledger.update_account(ctx.scope, ctx.broker, %{closed: true})

      assert ctx.broker.id in ids(Portfolios.account_choices(ctx.scope, ctx.portfolio).accounts)
    end
  end

  describe "update_portfolio/3" do
    test "sets the depot number and the Verrechnungskonto", ctx do
      giro = account_fixture(ctx.scope, %{name: "Giro", kind: :checking})

      assert {:ok, %Portfolio{} = portfolio} =
               Portfolios.update_portfolio(ctx.scope, ctx.portfolio, %{
                 "depot_number" => " 123 4472 ",
                 "reference_account_id" => to_string(giro.id)
               })

      assert %{depot_number: "123 4472", reference_account_id: giro_id} =
               Repo.get!(Portfolio, portfolio.id)

      assert giro_id == giro.id
      assert Portfolios.cash_account_portfolios(ctx.scope) == %{}
    end

    test "needs a Verrechnungskonto", ctx do
      assert {:error, changeset} =
               Portfolios.update_portfolio(ctx.scope, ctx.portfolio, %{
                 "reference_account_id" => ""
               })

      assert %{reference_account_id: ["can't be blank"]} = errors_on(changeset)
    end

    test "lets portfolios share a budget account, retired ones too", ctx do
      giro = account_fixture(ctx.scope, %{name: "Giro", kind: :checking})
      portfolio_fixture(ctx.scope, %{name: "Alt", retired: true, reference_account_id: giro.id})

      assert {:ok, _portfolio} =
               Portfolios.update_portfolio(ctx.scope, ctx.portfolio, %{
                 "reference_account_id" => to_string(giro.id)
               })

      assert reference_id(ctx.portfolio) == giro.id
    end

    test "refuses accounts the portfolio may not use", ctx do
      closed = account_fixture(ctx.scope, %{name: "Alt", closed: true})
      foreign = account_fixture(user_scope_fixture(), %{name: "Fremd"})

      for id <- [closed.id, foreign.id] do
        assert {:error, changeset} =
                 Portfolios.update_portfolio(ctx.scope, ctx.portfolio, %{
                   "reference_account_id" => to_string(id)
                 })

        assert %{reference_account_id: ["ist kein offenes Konto in Finanzen"]} =
                 errors_on(changeset)
      end

      assert reference_id(ctx.portfolio) == ctx.broker.id
    end

    test "refuses a tracking account that is another portfolio's Verrechnungskonto, a retired one's too",
         ctx do
      for retired <- [false, true] do
        taken = account_fixture(ctx.scope, %{name: "Vergeben"})

        portfolio_fixture(ctx.scope, %{
          name: "Anderes",
          retired: retired,
          reference_account_id: taken.id
        })

        assert {:error, changeset} =
                 Portfolios.update_portfolio(ctx.scope, ctx.portfolio, %{
                   "reference_account_id" => to_string(taken.id)
                 })

        assert %{reference_account_id: ["ist schon das Verrechnungskonto von „Anderes“"]} =
                 errors_on(changeset)
      end

      assert reference_id(ctx.portfolio) == ctx.broker.id
    end

    test "refuses a tracking account with transactions waiting in its register, not a budget account",
         ctx do
      unapproved = account_fixture(ctx.scope, %{name: "Unbestätigt"})
      proposed = account_fixture(ctx.scope, %{name: "Vorschlag"})
      giro = account_fixture(ctx.scope, %{name: "Giro", kind: :checking})

      for account <- [unapproved, giro] do
        {:ok, _transaction} =
          Ledger.create_transaction(ctx.scope, %{
            account_id: account.id,
            date: @friday,
            amount: 100,
            approved: false
          })
      end

      {:ok, existing} =
        Ledger.create_transaction(ctx.scope, %{
          account_id: proposed.id,
          date: @friday,
          amount: 100
        })

      {:ok, _proposal} =
        Ledger.create_transaction(ctx.scope, %{
          account_id: proposed.id,
          date: @friday,
          amount: 100,
          source: :file,
          matched_transaction_id: existing.id
        })

      for account <- [unapproved, proposed] do
        assert {:error, changeset} =
                 Portfolios.update_portfolio(ctx.scope, ctx.portfolio, %{
                   "reference_account_id" => to_string(account.id)
                 })

        assert %{
                 reference_account_id: [
                   "hat noch unbestätigte Buchungen oder Zuordnungsvorschläge"
                 ]
               } =
                 errors_on(changeset)
      end

      assert reference_id(ctx.portfolio) == ctx.broker.id

      {:ok, _transaction} =
        Ledger.create_transaction(ctx.scope, %{
          account_id: ctx.broker.id,
          date: @friday,
          amount: 100,
          approved: false
        })

      assert {:ok, _portfolio} =
               Portfolios.update_portfolio(ctx.scope, ctx.portfolio, %{
                 "depot_number" => "4472",
                 "reference_account_id" => to_string(ctx.broker.id)
               })

      assert {:ok, _portfolio} =
               Portfolios.update_portfolio(ctx.scope, ctx.portfolio, %{
                 "reference_account_id" => to_string(giro.id)
               })
    end

    test "refuses another user's portfolio", ctx do
      assert_raise FunctionClauseError, fn ->
        Portfolios.update_portfolio(user_scope_fixture(), ctx.portfolio, %{"depot_number" => "1"})
      end
    end

    test "moves the cash in the holdings and the sidebar along", ctx do
      security = security_fixture(quote_feed: :manual)
      price_fixture(security, @friday, price(100), :manual)

      transaction_fixture(ctx.scope, @friday,
        type: :inbound_delivery,
        portfolio_id: ctx.portfolio.id,
        security_id: security.id,
        shares: shares(10)
      )

      plan = account_fixture(ctx.scope, %{name: "Sparplan-Cash"})
      deposit(ctx.scope, ctx.broker, 300)
      deposit(ctx.scope, plan, 50)

      {:ok, _portfolio} =
        Portfolios.update_portfolio(ctx.scope, ctx.portfolio, %{
          "reference_account_id" => to_string(plan.id)
        })

      assert %{portfolios: [%{value: value}]} = Portfolios.sidebar(ctx.scope, @saturday)
      assert value == money(1_000) + money(50)

      holdings = Portfolios.holdings(ctx.scope, ctx.portfolio.id, @saturday)
      assert [%{accounts: [%{account: %{name: "Sparplan-Cash"}}]}] = holdings.groups

      all = Portfolios.holdings(ctx.scope, nil, @saturday)

      assert Enum.map(
               all.groups,
               &{&1.portfolio && &1.portfolio.name,
                ids(Enum.map(&1.accounts, fn row -> row.account end))}
             ) ==
               [{"Langfristig", [plan.id]}, {nil, [ctx.broker.id]}]
    end

    test "lists the new Verrechnungskonto's transactions with the portfolio, the booked ones as they are",
         ctx do
      giro = account_fixture(ctx.scope, %{name: "Giro"})
      old = deposit(ctx.scope, ctx.broker, 300)
      new = deposit(ctx.scope, giro, 50)
      led = Repo.get_by!(LedgerTransaction, depot_transaction_id: old.id)

      {:ok, portfolio} =
        Portfolios.update_portfolio(ctx.scope, ctx.portfolio, %{
          "reference_account_id" => to_string(giro.id)
        })

      shown =
        for {_month, transactions} <- Portfolios.transactions_by_month(ctx.scope, nil, portfolio),
            transaction <- transactions,
            do: transaction.id

      assert shown == [new.id]
      assert Repo.reload!(led).account_id == ctx.broker.id
      assert Repo.reload!(led).amount == money(300)
    end
  end
end
