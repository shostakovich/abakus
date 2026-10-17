defmodule AbakusWeb.Depot.SeparationTest do
  use AbakusWeb.ConnCase

  import Phoenix.LiveViewTest
  import Abakus.Depot.{PortfoliosFixtures, ReceiptsFixtures, SecuritiesFixtures}
  import Abakus.UsersFixtures

  alias Abakus.Depot.{FakeModel, Portfolios, Receipts}
  alias Abakus.LocalTime

  setup :register_and_log_in_user

  # The signed-in user's own portfolio, and another user's portfolio, cash account and
  # transactions in a security both may see.
  setup %{scope: scope} do
    yesterday = Date.add(LocalTime.today(), -1)
    security = security_fixture(quote_feed: :manual, name: "Weltaktie")
    price_fixture(security, yesterday, price(100), :manual)
    own = portfolio_fixture(scope, %{name: "Eigenes Depot"})

    other = user_scope_fixture()
    account = account_fixture(other, %{name: "Fremdes Konto"})

    portfolio =
      portfolio_fixture(other, %{name: "Fremdes Depot", reference_account_id: account.id})

    deposit =
      transaction_fixture(other, yesterday,
        type: :deposit,
        account_id: account.id,
        amount: money(7_777),
        note: "Fremde Einlage"
      )

    transaction_fixture(other, yesterday,
      type: :inbound_delivery,
      portfolio_id: portfolio.id,
      security_id: security.id,
      shares: shares(3)
    )

    %{own: own, other: other, account: account, portfolio: portfolio, deposit: deposit}
  end

  test "a user never sees another user's portfolios, cash accounts or transactions", ctx do
    paths = [
      ~p"/depot",
      ~p"/depot/holdings",
      ~p"/depot/holdings?#{[portfolio: ctx.portfolio.id]}",
      ~p"/depot/dividends",
      ~p"/depot/transactions",
      ~p"/depot/performance",
      ~p"/depot/performance?#{[portfolio: ctx.portfolio.id]}",
      ~p"/depot/securities"
    ]

    for path <- paths do
      {:ok, lv, html} = live(ctx.conn, path)

      assert has_element?(lv, "aside nav", "Eigenes Depot"), path

      for foreign <- ["Fremdes Depot", "Fremdes Konto", "7.777", "Fremde Einlage"],
          do: refute(html =~ foreign, "#{path} shows #{foreign}")

      refute has_element?(lv, "#transaction-#{ctx.deposit.id}"), path
    end
  end

  test "the transaction form offers only the user's own portfolios and accounts", ctx do
    {:ok, lv, _html} = live(ctx.conn, ~p"/depot/transactions")
    lv |> element("#depots-book") |> render_click()

    assert has_element?(lv, "#transaction_portfolio_id option", "Eigenes Depot")
    refute has_element?(lv, "#transaction_portfolio_id option", "Fremdes Depot")
    refute has_element?(lv, "#transaction_account_id option", "Fremdes Konto")
  end

  test "another user's transaction neither opens nor goes", ctx do
    {:ok, lv, _html} = live(ctx.conn, ~p"/depot/transactions")

    lv
    |> with_target("#transaction-dialog")
    |> render_click("edit", %{"id" => ctx.deposit.id})

    refute has_element?(lv, "#transaction-modal")
    assert {:error, :read_only} = Portfolios.delete_transaction(ctx.scope, ctx.deposit)
    assert Portfolios.get_transaction(ctx.other, ctx.deposit.id)
  end

  test "a user never sees another user's receipts", ctx do
    FakeModel.stub(fn _text -> {:ok, answer()} end)
    {:ok, :added} = Receipts.upload(ctx.other, pdf_file("fremd-eingang.pdf"), "fremd-eingang.pdf")
    await_recognition()
    [waiting] = Receipts.list_inbox(ctx.other)

    {:ok, [booked]} =
      Portfolios.book_transaction(
        ctx.other,
        Portfolios.transaction_choices(ctx.other),
        %{
          "kind" => "deposit",
          "date" => "2026-10-01",
          "amount" => "1",
          "account_id" => ctx.account.id
        },
        {pdf_file("fremd-gebucht.pdf"), "fremd-gebucht.pdf"}
      )

    {:ok, transactions, html} = live(ctx.conn, ~p"/depot/transactions")
    refute html =~ "fremd-gebucht.pdf"

    {:ok, lv, html} = live(ctx.conn, ~p"/depot/receipts")

    refute has_element?(lv, "#inbox")
    refute has_element?(lv, "#inbox-count")
    refute has_element?(transactions, sidebar_link("/budget/import") <> " .badge")
    refute html =~ "fremd-eingang.pdf"

    lv
    |> with_target("#transaction-dialog")
    |> render_click("open_receipt", %{"id" => waiting.id})

    refute has_element?(lv, "#transaction-modal")
    assert render(lv) =~ "Dieser Beleg liegt nicht mehr im Eingang."

    render_click(lv, "discard", %{"id" => waiting.id})
    assert [%{id: id}] = Receipts.list_inbox(ctx.other)
    assert id == waiting.id

    assert ctx.conn |> get(~p"/depot/receipts/#{waiting.id}") |> response(404)
    assert ctx.conn |> get(~p"/depot/receipts/#{booked.receipt_id}") |> response(404)
  end
end
