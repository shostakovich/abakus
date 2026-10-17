defmodule AbakusWeb.Depot.TransactionDialogTest do
  use AbakusWeb.ConnCase

  import Phoenix.LiveViewTest
  import Abakus.Depot.{PortfoliosFixtures, SecuritiesFixtures}

  alias Abakus.Depot.Portfolios
  alias Abakus.LocalTime

  setup :register_and_log_in_user

  setup %{scope: scope} do
    account = account_fixture(scope, name: "Verrechnungskonto")
    portfolio = portfolio_fixture(scope, reference_account_id: account.id)
    %{account: account, portfolio: portfolio, security: security_fixture()}
  end

  defp open_dialog(conn) do
    {:ok, lv, _html} = live(conn, ~p"/depot/holdings")
    lv |> element("#depots-book") |> render_click()
    lv
  end

  defp change(lv, params, target) do
    lv
    |> form("#transaction-form", transaction: params)
    |> render_change(%{"_target" => ["transaction", target]})
  end

  test "opens from the Depots pages and on the phone with the portfolio's reference account",
       ctx do
    {:ok, lv, _html} = live(ctx.conn, ~p"/depot/holdings")
    refute has_element?(lv, "#transaction-modal")

    lv |> element("#fab-book") |> render_click()

    assert has_element?(lv, "#transaction-modal h2", "Buchung erfassen")
    assert has_element?(lv, "input[name='transaction[kind]'][value=purchase][checked]")
    assert has_element?(lv, "#transaction_account_id option[selected]", "Verrechnungskonto")

    assert has_element?(
             lv,
             "#transaction_date[value='#{Date.to_iso8601(LocalTime.today())}']"
           )

    close_modal(lv, "#transaction-cancel", "transaction-modal")
    refute has_element?(lv, "#transaction-modal")
  end

  test "computes the amount live and warns about an overwritten one", ctx do
    lv = open_dialog(ctx.conn)
    params = %{security_id: ctx.security.id, shares: "10", price: "100,0000", fees: "1,00"}

    change(lv, params, "fees")
    assert has_element?(lv, "#transaction_amount[value='1.001,00']")

    params = %{params | shares: "31,0700", price: "12,0699", fees: "0,00"}
    change(lv, params, "price")
    assert has_element?(lv, "#transaction_amount[value='375,01']")
    assert has_element?(lv, "#transaction_shares[value='31,0700']")
    refute has_element?(lv, "#transaction_amount-help")

    change(lv, Map.put(params, :amount, "375,02"), "amount")

    assert lv |> element("#transaction_amount-help") |> render() =~
             "Stück × Kurs ergibt 375,01 €"

    lv |> form("#transaction-form") |> render_submit()

    assert render(lv) =~ "Buchung gespeichert."
    refute has_element?(lv, "#transaction-modal")
    assert [%{type: :buy, amount: 37_502}] = Portfolios.list_transactions(ctx.scope)
  end

  test "books a purchase without an account as an inbound delivery", ctx do
    lv = open_dialog(ctx.conn)
    params = %{security_id: ctx.security.id, shares: "10", price: "100", account_id: ""}
    change(lv, params, "account_id")

    assert lv |> element("label[for=transaction_amount]") |> render() =~ "ohne Konto"

    lv |> form("#transaction-form") |> render_submit()

    assert [%{type: :inbound_delivery, account_id: nil, source: :manual}] =
             Portfolios.list_transactions(ctx.scope)
  end

  test "books a dividend removed at once as two transactions", ctx do
    lv = open_dialog(ctx.conn)
    change(lv, %{kind: "dividend"}, "kind")
    assert has_element?(lv, "#transaction_gross")
    refute has_element?(lv, "#transaction_price")

    params = %{
      kind: "dividend",
      security_id: ctx.security.id,
      gross: "100,00",
      taxes: "18,50",
      remove_at_once: "true"
    }

    change(lv, params, "taxes")
    assert has_element?(lv, "#transaction_amount[value='81,50']")

    lv |> form("#transaction-form") |> render_submit()

    assert render(lv) =~ "Dividende und Entnahme gebucht."

    assert [%{type: :dividend, amount: 8_150}, %{type: :removal, amount: 8_150}] =
             Portfolios.list_transactions(ctx.scope)
  end

  test "refuses a sale beyond the holding", ctx do
    lv = open_dialog(ctx.conn)
    params = %{kind: "sale", security_id: ctx.security.id, shares: "6", price: "100"}
    change(lv, params, "kind")

    html = lv |> form("#transaction-form") |> render_submit()

    assert html =~ "Übersteigt den Bestand von 0 Stück"
    assert has_element?(lv, "#transaction-modal")
    assert Portfolios.list_transactions(ctx.scope) == []
  end

  test "attaches an uploaded PDF receipt", ctx do
    lv = open_dialog(ctx.conn)
    change(lv, %{kind: "deposit", amount: "500"}, "amount")

    lv
    |> file_input("#transaction-form", :receipt, [
      %{name: "beleg.pdf", content: "%PDF-1.4\n%%EOF\n", type: "application/pdf"}
    ])
    |> render_upload("beleg.pdf")

    lv |> form("#transaction-form") |> render_submit()

    assert [%{type: :deposit, amount: 50_000, receipt_id: receipt_id}] =
             Portfolios.list_transactions(ctx.scope)

    assert receipt_id
  end

  test "updates the sidebar once booked", ctx do
    security = security_fixture(quote_feed: :manual)
    price_fixture(security, Date.add(LocalTime.today(), -1), price(123), :manual)
    lv = open_dialog(ctx.conn)
    params = %{security_id: security.id, shares: "10", price: "100", account_id: ""}
    change(lv, params, "account_id")
    lv |> form("#transaction-form") |> render_submit()

    path = ~p"/depot/holdings?#{[portfolio: ctx.portfolio.id]}"
    assert lv |> element(sidebar_link(path)) |> render() =~ "1.230,00"
  end
end
