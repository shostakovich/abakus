defmodule AbakusWeb.RegisterDepotCashTest do
  use AbakusWeb.ConnCase

  import Phoenix.LiveViewTest
  import Abakus.Depot.PortfoliosFixtures, only: [portfolio_fixture: 2]
  import Abakus.DomainFixtures

  alias Abakus.Ledger
  alias AbakusWeb.Depot.Components

  setup :register_and_log_in_user

  setup %{scope: scope} do
    giro = account_fixture(name: "Comdirect", kind: :checking)
    savings = account_fixture(name: "Tagesgeld", kind: :tracking)
    broker = account_fixture(name: "Scalable Capital", kind: :tracking)
    portfolio_fixture(scope, %{name: "Comdirect Depot", reference_account_id: giro.id})
    portfolio = portfolio_fixture(scope, %{name: "Langfristig", reference_account_id: broker.id})

    {:ok, deposit} =
      Ledger.create_transaction(budget_scope(), %{
        account_id: giro.id,
        date: ~D[2026-10-01],
        amount: -100_000,
        payee_id: broker.transfer_payee.id,
        category_id: category_fixture(name: "Sparen").id,
        memo: "Sparrate"
      })

    interest = transaction_fixture(account_id: broker.id, date: ~D[2026-10-02], amount: 123)

    %{
      giro: giro,
      savings: savings,
      broker: broker,
      portfolio: portfolio,
      deposit: deposit,
      interest: interest
    }
  end

  test "Alle Konten shows none of a portfolio's cash, a budget account as Verrechnungskonto its transfer",
       c do
    {:ok, view, _html} = live(c.conn, ~p"/budget/accounts/all")

    assert has_element?(view, "#tx-#{c.deposit.id}")
    refute has_element?(view, "#tx-#{c.deposit.transfer_transaction_id}")
    refute has_element?(view, "#tx-#{c.interest.id}")
    assert has_element?(view, "#balance-tracking", "0,00\u00A0€")
  end

  test "no account picker offers a portfolio's cash", c do
    for path <- [~p"/budget/accounts/all", ~p"/budget/accounts/#{c.giro}"] do
      {:ok, view, _html} = live(c.conn, path)
      view |> element("#new-transaction") |> render_click()
      html = render(view)

      refute has_element?(view, ~s|#tx-account option[value="#{c.broker.id}"]|)
      refute html =~ ~s|data-value="a:#{c.broker.id}"|
      assert html =~ ~s|data-value="a:#{c.savings.id}"|
    end
  end

  test "a transfer to a portfolio's cash keeps it when edited in the budget account", c do
    {:ok, view, _html} = live(c.conn, ~p"/budget/accounts/#{c.giro}")
    view |> element("#tx-#{c.deposit.id} td.app-payee") |> render_click()
    view |> element("#tx-#{c.deposit.id} td.app-payee") |> render_click()

    assert has_element?(view, ~s|#tx-payee[value="⇄ Scalable Capital"]|)
    view |> form("#tx-form", transaction: %{memo: "Sparrate Oktober"}) |> render_submit()

    assert %{memo: "Sparrate Oktober", payee_id: payee_id} =
             Ledger.get_transaction!(budget_scope(), c.deposit.id)

    assert payee_id == c.broker.transfer_payee.id
  end

  test "a transfer to a portfolio's cash keeps it when edited in Alle Konten", c do
    {:ok, view, _html} = live(c.conn, ~p"/budget/accounts/all")
    view |> element("#tx-#{c.deposit.id} td.app-payee") |> render_click()
    view |> element("#tx-#{c.deposit.id} td.app-payee") |> render_click()

    assert has_element?(view, ~s|#tx-payee[value="⇄ Scalable Capital"]|)
    view |> form("#tx-form", transaction: %{memo: "Sparrate Oktober"}) |> render_submit()

    assert %{
             memo: "Sparrate Oktober",
             payee_id: payee_id,
             transfer_transaction_id: counterpart_id
           } =
             Ledger.get_transaction!(budget_scope(), c.deposit.id)

    assert payee_id == c.broker.transfer_payee.id
    assert Ledger.get_transaction!(budget_scope(), counterpart_id).account_id == c.broker.id
  end

  test "a cash account's register leads to its portfolio in the Depot", c do
    path = Components.depots_path(:holdings, c.portfolio.id)

    assert {:error, {:live_redirect, %{to: ^path}}} =
             live(c.conn, ~p"/budget/accounts/#{c.broker}")

    {:ok, view, _html} = live(c.conn, path)
    assert view |> element("#account-#{c.broker.id}") |> render() =~ "Cash"
  end

  test "a retired portfolio's cash stays the Depot's", c do
    old_cash = account_fixture(name: "Alt-Cash", kind: :tracking)

    retired =
      portfolio_fixture(c.scope, %{name: "Alt", retired: true, reference_account_id: old_cash.id})

    old_interest = transaction_fixture(account_id: old_cash.id, amount: 77)

    {:ok, view, _html} = live(c.conn, ~p"/budget/accounts/all")
    refute has_element?(view, "#tx-#{old_interest.id}")
    refute has_element?(view, ~s|a[href="/budget/accounts/#{old_cash.id}"]|)

    path = Components.depots_path(:holdings, retired.id)

    assert {:error, {:live_redirect, %{to: ^path}}} =
             live(c.conn, ~p"/budget/accounts/#{old_cash}")
  end

  test "a budget account as Verrechnungskonto stays the budget's", c do
    {:ok, view, _html} = live(c.conn, ~p"/budget/accounts/#{c.giro}")

    assert has_element?(view, "#register-title", "Comdirect")
    assert has_element?(view, "#tx-#{c.deposit.id}")
    assert has_element?(view, ~s|a[href="/budget/accounts/#{c.giro.id}"]|)
  end
end
