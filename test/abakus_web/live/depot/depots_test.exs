defmodule AbakusWeb.Depot.DepotsTest do
  use AbakusWeb.ConnCase

  import Phoenix.LiveViewTest
  import Abakus.Depot.{PortfoliosFixtures, SecuritiesFixtures}

  alias Abakus.Depot.BudgetFeed
  alias Abakus.{LocalTime, Repo}

  setup :register_and_log_in_user

  setup %{scope: scope} do
    yesterday = Date.add(LocalTime.today(), -1)
    long_account = account_fixture(scope, %{name: "Konto Langfristig"})
    play_account = account_fixture(scope, %{name: "Konto Spielgeld"})
    long = portfolio_fixture(scope, %{name: "Langfristig", reference_account_id: long_account.id})
    play = portfolio_fixture(scope, %{name: "Spielgeld", reference_account_id: play_account.id})

    deposit =
      transaction_fixture(scope, yesterday,
        type: :deposit,
        account_id: long_account.id,
        amount: money(1_000)
      )

    long_buy = buy(scope, long, long_account, "All-World", yesterday)
    play_buy = buy(scope, play, play_account, "Moonshot", yesterday)
    long_dividend = dividend(scope, long_buy, long_account, 30)
    play_dividend = dividend(scope, play_buy, play_account, 7)

    %{
      long: long,
      play: play,
      deposit: deposit,
      long_buy: long_buy,
      play_buy: play_buy,
      long_dividend: long_dividend,
      play_dividend: play_dividend
    }
  end

  defp buy(scope, portfolio, account, name, date) do
    security =
      security_fixture(
        name: name,
        quote_feed: :manual,
        latest_date: LocalTime.today(),
        latest_close: price(100)
      )

    transaction_fixture(scope, date,
      type: :buy,
      portfolio_id: portfolio.id,
      account_id: account.id,
      security_id: security.id,
      shares: shares(5),
      amount: money(500)
    )
  end

  defp dividend(scope, buy, account, net) do
    transaction_fixture(scope, LocalTime.today(),
      type: :dividend,
      account_id: account.id,
      security_id: buy.security_id,
      shares: shares(5),
      amount: money(net)
    )
  end

  defp tab_paths(lv) do
    lv
    |> render()
    |> LazyHTML.from_document()
    |> LazyHTML.query("#depots-tabs a")
    |> LazyHTML.attribute("href")
  end

  test "all portfolios have five tabs and „Buchung erfassen“", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/depot/holdings")

    assert has_element?(lv, "h1", "Depots")
    assert has_element?(lv, "#depots-book", "Buchung erfassen")

    assert tab_paths(lv) ==
             ~w(/depot/holdings /depot/transactions /depot/dividends /depot/performance /depot/securities)
  end

  test "a portfolio has its name and the tabs without Wertpapiere, each keeping it", ctx do
    {:ok, lv, _html} = live(ctx.conn, ~p"/depot/transactions?#{[portfolio: ctx.long.id]}")

    assert has_element?(lv, "h1", "Langfristig")
    assert has_element?(lv, "#depots-book", "Buchung erfassen")

    assert tab_paths(lv) ==
             Enum.map(
               ~w(holdings transactions dividends performance),
               &"/depot/#{&1}?portfolio=#{ctx.long.id}"
             )

    assert has_element?(
             lv,
             sidebar_link(~p"/depot/holdings?#{[portfolio: ctx.long.id]}") <>
               "[aria-current=page]"
           )
  end

  test "a portfolio of the budget owner is its account, whose register is its tab Register",
       ctx do
    :ok = BudgetFeed.sync_accounts()
    long = Repo.reload!(ctx.long)
    register = ~p"/budget/accounts/#{long.budget_account_id}"
    holdings = ~p"/depot/holdings?#{[portfolio: long.id]}"

    {:ok, lv, _html} = live(ctx.conn, ~p"/depot/holdings?#{[portfolio: long.id]}")

    assert tab_paths(lv) ==
             ["/depot/holdings?portfolio=#{long.id}", register] ++
               Enum.map(
                 ~w(transactions dividends performance),
                 &"/depot/#{&1}?portfolio=#{long.id}"
               )

    {:ok, lv, _html} = live(ctx.conn, register)

    assert has_element?(lv, ~s(#depots-tabs a[href="#{register}"][aria-current=page]), "Register")
    assert has_element?(lv, ~s(#depots-tabs a[href="#{holdings}"]), "Bestand")
    assert has_element?(lv, sidebar_link(holdings) <> "[aria-current=page]")
    refute has_element?(lv, "#side-account-#{long.budget_account_id}")
  end

  test "Buchungen of a portfolio are its own and its reference account's", ctx do
    {:ok, lv, _html} = live(ctx.conn, ~p"/depot/transactions?#{[portfolio: ctx.long.id]}")

    for transaction <- [ctx.deposit, ctx.long_buy, ctx.long_dividend],
        do: assert(has_element?(lv, "#transaction-#{transaction.id}"))

    for transaction <- [ctx.play_buy, ctx.play_dividend],
        do: refute(has_element?(lv, "#transaction-#{transaction.id}"))
  end

  test "Dividenden of a portfolio count only its own", ctx do
    {:ok, lv, _html} = live(ctx.conn, ~p"/depot/dividends?#{[portfolio: ctx.play.id]}")
    assert lv |> element("#this-year .stat-value") |> render() =~ "7 €"

    {:ok, lv, _html} = live(ctx.conn, ~p"/depot/dividends")
    assert lv |> element("#this-year .stat-value") |> render() =~ "37 €"
  end

  test "the portfolio menu keeps the tab and its filter", ctx do
    {:ok, lv, _html} = live(ctx.conn, ~p"/depot/transactions?filter=earnings")

    lv |> element("#portfolio-menu a", "Spielgeld") |> render_click()

    assert_patch(lv, ~p"/depot/transactions?#{[filter: "earnings", portfolio: ctx.play.id]}")
    assert has_element?(lv, "#transaction-#{ctx.play_dividend.id}")
    refute has_element?(lv, "#transaction-#{ctx.long_dividend.id}")
  end
end
