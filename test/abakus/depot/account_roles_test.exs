defmodule Abakus.Depot.AccountRolesTest do
  use Abakus.DataCase

  import Abakus.Depot.PortfoliosFixtures
  import Abakus.UsersFixtures

  alias Abakus.Depot.AccountRoles
  alias Abakus.Depot.Portfolios.Account
  alias Abakus.DomainFixtures

  setup do
    owner = user_scope_fixture()
    portfolio = portfolio_fixture(owner, %{name: "Broker"})
    giro = DomainFixtures.account_fixture(name: "Giro", kind: :checking)
    %{owner: owner, portfolio: portfolio, giro: giro}
  end

  defp role(account), do: account |> Repo.reload!() |> Account.role()

  test "makes a Verrechnungskonto a budget account, a portfolio's cash or neither", c do
    account = account_fixture(c.owner, %{name: "Giro-Verrechnung"})
    assert AccountRoles.without_role(c.owner) |> Enum.map(& &1.id) == [account.id]

    assert {:ok, _account} =
             AccountRoles.set_role(c.owner, account, "budget_account:#{c.giro.id}")

    assert role(account) == {:budget_account, c.giro.id}
    assert AccountRoles.without_role(c.owner) == []

    account = Repo.reload!(account)

    assert {:ok, _account} =
             AccountRoles.set_role(c.owner, account, "portfolio_cash:#{c.portfolio.id}")

    assert role(account) == {:portfolio_cash, c.portfolio.id}
    assert AccountRoles.cash_account_ids(c.portfolio) == [account.id]

    account = Repo.reload!(account)
    assert {:ok, _account} = AccountRoles.set_role(c.owner, account, "none")
    assert role(account) == :none
    assert AccountRoles.cash_account_ids(c.portfolio) == []
    assert AccountRoles.without_role(c.owner) == []
  end

  test "makes only the budget owner's Verrechnungskonten budget accounts", c do
    member = user_scope_fixture()
    account = account_fixture(member)

    assert {:error, "Nur wer das Budget führt, kann ein Budgetkonto wählen."} =
             AccountRoles.set_role(member, account, "budget_account:#{c.giro.id}")

    assert AccountRoles.choices(member, account).budget_accounts == []
  end

  test "gives a budget account to at most one Verrechnungskonto", c do
    first = account_fixture(c.owner, %{name: "Erstes"})
    second = account_fixture(c.owner, %{name: "Zweites"})
    {:ok, _first} = AccountRoles.set_role(c.owner, first, "budget_account:#{c.giro.id}")

    assert AccountRoles.choices(c.owner, second).budget_accounts == []
    assert [%{id: id}] = AccountRoles.choices(c.owner, Repo.reload!(first)).budget_accounts
    assert id == c.giro.id

    assert {:error, "ist schon die Rolle eines anderen Verrechnungskontos"} =
             AccountRoles.set_role(c.owner, second, "budget_account:#{c.giro.id}")
  end

  test "refuses a tracking, closed or fed account, another user's portfolio and an unknown role",
       c do
    account = account_fixture(c.owner)
    tracking = DomainFixtures.account_fixture(name: "Depot", kind: :tracking)
    closed = DomainFixtures.account_fixture(name: "Alt", kind: :checking, closed: true)

    kasse =
      DomainFixtures.account_fixture(name: "Kasse", kind: :checking, fed_by: :shared_expenses)

    theirs = portfolio_fixture(user_scope_fixture())

    for budget_account <- [tracking, closed, kasse] do
      assert {:error, "Das ist kein offenes Budgetkonto."} =
               AccountRoles.set_role(c.owner, account, "budget_account:#{budget_account.id}")
    end

    assert {:error, "Das ist keins deiner Depots."} =
             AccountRoles.set_role(c.owner, account, "portfolio_cash:#{theirs.id}")

    for param <- ["", "budget_account:x", "anything"] do
      assert {:error, "Wähle eine Rolle."} = AccountRoles.set_role(c.owner, account, param)
    end

    assert role(account) == nil
    assert [%{id: id}] = AccountRoles.choices(c.owner, account).budget_accounts
    assert id == c.giro.id
  end

  test "makes a Verrechnungskonto the cash of a retired portfolio only if it already is", c do
    retired = portfolio_fixture(c.owner, %{name: "Alt", retired: true})
    account = account_fixture(c.owner)

    assert {:error, "Das ist keins deiner Depots."} =
             AccountRoles.set_role(c.owner, account, "portfolio_cash:#{retired.id}")

    cash = account_fixture(c.owner, %{name: "Cash", cash_of_portfolio_id: retired.id})

    assert {:ok, _cash} = AccountRoles.set_role(c.owner, cash, "portfolio_cash:#{retired.id}")
  end

  test "lists no retired Verrechnungskonto as without role", c do
    account_fixture(c.owner, %{retired: true})

    assert AccountRoles.without_role(c.owner) == []
  end
end
