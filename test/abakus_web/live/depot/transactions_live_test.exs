defmodule AbakusWeb.Depot.TransactionsLiveTest do
  use AbakusWeb.ConnCase

  import Phoenix.LiveViewTest
  import Abakus.Depot.{PortfoliosFixtures, SecuritiesFixtures}
  import Abakus.UsersFixtures

  alias Abakus.Depot.{FakeSymbolSearch, Portfolios}
  alias Abakus.Depot.Portfolios.Transaction
  alias Abakus.Depot.Securities.Security
  alias Abakus.Repo

  setup :register_and_log_in_user

  setup %{scope: scope} do
    account = account_fixture(scope, name: "Verrechnungskonto")
    portfolio = portfolio_fixture(scope, reference_account_id: account.id)
    %{account: account, portfolio: portfolio, security: security_fixture()}
  end

  defp book(ctx, params, receipt \\ nil) do
    params = Map.merge(%{"date" => "2026-10-01", "account_id" => ctx.account.id}, params)

    {:ok, transactions} =
      Portfolios.book_transaction(
        ctx.scope,
        Portfolios.transaction_choices(ctx.scope),
        params,
        receipt
      )

    transactions
  end

  defp change(lv, params, target) do
    lv
    |> form("#transaction-form", transaction: params)
    |> render_change(%{"_target" => ["transaction", target]})
  end

  test "lists the transactions by month, newest first, from the tab", ctx do
    book(ctx, %{"kind" => "deposit", "amount" => "1.500,00", "date" => "2026-09-30"})

    book(ctx, %{
      "kind" => "purchase",
      "portfolio_id" => ctx.portfolio.id,
      "security_id" => ctx.security.id,
      "shares" => "20",
      "price" => "158,90",
      "fees" => "1"
    })

    {:ok, lv, _html} = live(ctx.conn, ~p"/depot/holdings")

    {:ok, lv, _html} =
      lv
      |> element(~s(#depots-tabs a[href="/depot/transactions"]))
      |> render_click()
      |> follow_redirect(ctx.conn)

    assert has_element?(lv, ~s(#depots-tabs a[href="/depot/transactions"][aria-current=page]))
    assert has_element?(lv, sidebar_link("/depot/holdings") <> "[aria-current=page]")
    assert has_element?(lv, ~s(nav.dock a[href="/depot/holdings"][aria-current=page]))

    assert has_element?(lv, "#month-2026-10-01", "Oktober 2026")
    october = lv |> element("li[data-month='2026-10-01']") |> render()
    assert october =~ "Kauf\u2060\u00A0· Vanguard FTSE All-World"
    assert october =~ "20 Stück à 158,90\u00A0€"
    assert october =~ "Gebühren 1,00\u00A0€"
    assert october =~ "−3.179,00\u00A0€"

    september = lv |> element("li[data-month='2026-09-01']") |> render()
    assert september =~ "Einlage"
    assert september =~ "+1.500,00\u00A0€"
  end

  test "the page's own „Buchung erfassen“ shows from 768 px", ctx do
    {:ok, lv, _html} = live(ctx.conn, ~p"/depot/transactions")
    assert has_element?(lv, "#depots-book.max-md\\:hidden")
    refute has_element?(lv, "#depots-book.max-lg\\:hidden")
  end

  test "invites the first booking while there is none", ctx do
    {:ok, lv, _html} = live(ctx.conn, ~p"/depot/transactions")

    assert has_element?(lv, "#transactions-empty h2", "Noch keine Buchungen")
    assert has_element?(lv, "#transactions-empty img[src^='/images/plush/clipboard-list']")
  end

  test "shows each booking with the plush of its kind", ctx do
    plushes =
      for {type, plush} <- [dividend: "coins", buy: "layers", deposit: "wallet"] do
        transaction =
          transaction_fixture(ctx.scope, ~D[2026-10-01],
            type: type,
            account_id: ctx.account.id,
            security_id: if(type != :deposit, do: ctx.security.id),
            portfolio_id: if(type == :buy, do: ctx.portfolio.id),
            shares: if(type == :buy, do: shares(1)),
            amount: money(10)
          )

        {transaction.id, plush}
      end

    {:ok, lv, _html} = live(ctx.conn, ~p"/depot/transactions")

    for {id, plush} <- plushes,
        do: assert(has_element?(lv, "#transaction-#{id} img[src^='/images/plush/#{plush}']"))
  end

  test "rounds the price per share as the holdings do", ctx do
    # 1,00 € over 0,01015596 shares is 98,46434999… €.
    transaction_fixture(ctx.scope, ~D[2026-10-01], %{
      type: :buy,
      portfolio_id: ctx.portfolio.id,
      account_id: ctx.account.id,
      security_id: ctx.security.id,
      shares: 1_015_596,
      amount: 100
    })

    {:ok, lv, _html} = live(ctx.conn, ~p"/depot/transactions")
    assert lv |> element("li[data-month='2026-10-01']") |> render() =~ "à 98,4644\u00A0€"
  end

  test "filters purchases and sales, earnings and account", ctx do
    book(ctx, %{"kind" => "deposit", "amount" => "100"})
    book(ctx, %{"kind" => "dividend", "security_id" => ctx.security.id, "gross" => "10"})

    {:ok, lv, _html} = live(ctx.conn, ~p"/depot/transactions?filter=earnings")

    assert has_element?(
             lv,
             "li[id^=transaction-]",
             "Dividende\u2060\u00A0· Vanguard FTSE All-World"
           )

    refute has_element?(lv, "li[id^=transaction-]", "Einlage")

    lv |> element("#transaction-filter a", "Konto") |> render_click()
    assert_patch(lv, ~p"/depot/transactions?filter=account")
    assert has_element?(lv, "li[id^=transaction-]", "Einlage")
    refute has_element?(lv, "li[id^=transaction-]", "Dividende")

    lv |> element("#transaction-filter a", "Käufe und Verkäufe") |> render_click()
    assert has_element?(lv, "#transactions-empty", "Keine Buchungen dieser Art.")
  end

  test "a transaction of a type the form does not know shows read-only and deletes", ctx do
    other = portfolio_fixture(ctx.scope, name: "Anderes Depot")

    transfer =
      transaction_fixture(ctx.scope, ~D[2026-10-01],
        type: :security_transfer,
        portfolio_id: ctx.portfolio.id,
        other_portfolio_id: other.id,
        security_id: ctx.security.id,
        shares: shares(3)
      )

    {:ok, lv, _html} = live(ctx.conn, ~p"/depot/transactions")
    lv |> element("#transaction-#{transfer.id} button") |> render_click()

    assert has_element?(lv, "#transaction-modal h2", "Buchung")
    refute has_element?(lv, "#transaction-form")
    refute has_element?(lv, "#transaction-book")
    assert has_element?(lv, "#transaction-facts", "Depotwechsel")
    assert has_element?(lv, "#transaction-facts", "Anderes Depot")
    assert has_element?(lv, "#transaction-facts div", ~r/Stück\s+3$/)
    assert has_element?(lv, "#transaction-read-only", "Diese Buchungsart lässt sich nur löschen.")

    confirm_click(lv, "#transaction-delete", "Diese Buchung löschen?")

    assert render(lv) =~ "Buchung gelöscht."
    refute has_element?(lv, "#transaction-#{transfer.id}")
    assert Portfolios.list_transactions(ctx.scope) == []
  end

  test "edits a booked transaction, which updates the overview", ctx do
    [deposit] = book(ctx, %{"kind" => "deposit", "amount" => "100"})
    {:ok, lv, _html} = live(ctx.conn, ~p"/depot/transactions")

    lv |> element("#transaction-#{deposit.id} button") |> render_click()
    assert has_element?(lv, "#transaction-modal h2", "Buchung bearbeiten")
    assert has_element?(lv, "input[name='transaction[kind]'][value=deposit][checked]")
    assert has_element?(lv, "#transaction_amount[value='100,00']")
    refute has_element?(lv, "#transaction-form button", "Buchen")

    change(lv, %{kind: "deposit", amount: "250"}, "amount")
    lv |> form("#transaction-form") |> render_submit()

    assert render(lv) =~ "Buchung gespeichert."
    assert lv |> element("#transaction-#{deposit.id}") |> render() =~ "+250,00\u00A0€"
    assert [%{id: id, amount: 25_000}] = Portfolios.list_transactions(ctx.scope)
    assert id == deposit.id

    {:ok, _lv, html} = live(ctx.conn, ~p"/depot")
    assert html =~ "250"
  end

  test "edits a transaction on a retired portfolio and closed account", ctx do
    [purchase] =
      book(ctx, %{
        "kind" => "purchase",
        "portfolio_id" => ctx.portfolio.id,
        "security_id" => ctx.security.id,
        "shares" => "2",
        "price" => "10"
      })

    Repo.update!(Ecto.Changeset.change(ctx.portfolio, retired: true))
    Repo.update!(Ecto.Changeset.change(ctx.account, closed: true))

    {:ok, lv, _html} = live(ctx.conn, ~p"/depot/transactions")
    lv |> element("#transaction-#{purchase.id} button") |> render_click()
    assert has_element?(lv, "#transaction_portfolio_id option[selected]", "Langfristig")
    assert has_element?(lv, "#transaction_account_id option[selected]", "Verrechnungskonto")

    lv |> form("#transaction-form") |> render_submit()

    assert render(lv) =~ "Buchung gespeichert."
    assert [%{type: :buy, portfolio_id: portfolio_id}] = Portfolios.list_transactions(ctx.scope)
    assert portfolio_id == ctx.portfolio.id
  end

  test "refuses to delete a purchase a later sale needs", ctx do
    trade = %{
      "portfolio_id" => ctx.portfolio.id,
      "security_id" => ctx.security.id,
      "price" => "10"
    }

    [purchase] = book(ctx, Map.merge(trade, %{"kind" => "purchase", "shares" => "2"}))
    book(ctx, Map.merge(trade, %{"kind" => "sale", "shares" => "2"}))

    {:ok, lv, _html} = live(ctx.conn, ~p"/depot/transactions")
    lv |> element("#transaction-#{purchase.id} button") |> render_click()
    confirm_click(lv, "#transaction-delete", "Diese Buchung löschen?")

    assert has_element?(lv, "#transaction-error", "fiele der Bestand später unter null")
    assert has_element?(lv, "#transaction-modal")
    assert length(Portfolios.list_transactions(ctx.scope)) == 2

    lv |> form("#transaction-form") |> render_change(%{"transaction" => %{"shares" => "3"}})
    refute has_element?(lv, "#transaction-error")
  end

  test "does not open another user's transaction", ctx do
    other = user_scope_fixture()
    account = account_fixture(other)

    {:ok, [foreign]} =
      Portfolios.book_transaction(other, Portfolios.transaction_choices(other), %{
        "kind" => "deposit",
        "date" => "2026-10-01",
        "amount" => "1",
        "account_id" => account.id
      })

    {:ok, lv, _html} = live(ctx.conn, ~p"/depot/transactions")
    lv |> with_target("#transaction-dialog") |> render_click("edit", %{"id" => foreign.id})

    refute has_element?(lv, "#transaction-modal")
    assert Repo.get(Transaction, foreign.id)
  end

  test "a transaction deleted in another tab is gone", ctx do
    [first, second] =
      for amount <- ["100", "200"], do: hd(book(ctx, %{"kind" => "deposit", "amount" => amount}))

    {:ok, lv, _html} = live(ctx.conn, ~p"/depot/transactions")
    {:ok, _} = Portfolios.delete_transaction(ctx.scope, first)
    lv |> with_target("#transaction-dialog") |> render_click("edit", %{"id" => first.id})

    assert render(lv) =~ "Diese Buchung gibt es nicht mehr."
    refute has_element?(lv, "#transaction-modal")
    refute has_element?(lv, "#transaction-#{first.id}")

    lv |> element("#transaction-#{second.id} button") |> render_click()
    {:ok, _} = Portfolios.delete_transaction(ctx.scope, second)
    lv |> form("#transaction-form") |> render_submit()

    assert render(lv) =~ "Diese Buchung gibt es nicht mehr."
    assert Portfolios.list_transactions(ctx.scope) == []
  end

  test "deletes a booked transaction and its receipt", ctx do
    path = Path.join(System.tmp_dir!(), "receipt-#{System.unique_integer([:positive])}.pdf")
    File.write!(path, "%PDF-1.4\nzu löschen\n%%EOF\n")
    on_exit(fn -> File.rm(path) end)
    [deposit] = book(ctx, %{"kind" => "deposit", "amount" => "100"}, {path, "beleg.pdf"})
    file = Portfolios.receipt_file(Repo.preload(deposit, :receipt).receipt)

    {:ok, lv, _html} = live(ctx.conn, ~p"/depot/transactions")

    assert has_element?(
             lv,
             "#transaction-#{deposit.id} a[href='/depot/receipts/#{deposit.receipt_id}']"
           )

    # A finger gets 44 px to hit the PDF badge.
    for suffix <- ["", "-phone"] do
      assert has_element?(
               lv,
               "#transaction-#{deposit.id}-receipt#{suffix}.pointer-coarse\\:min-h-11.pointer-coarse\\:min-w-11"
             )
    end

    lv |> element("#transaction-#{deposit.id} button") |> render_click()
    assert has_element?(lv, "#transaction-form a", "beleg.pdf")
    confirm_click(lv, "#transaction-delete", "Diese Buchung löschen?")

    assert render(lv) =~ "Buchung gelöscht."
    refute has_element?(lv, "#transaction-#{deposit.id}")
    assert Portfolios.list_transactions(ctx.scope) == []
    refute File.exists?(file)
  end

  test "a receipt picked before deleting does not hold up the next booking", ctx do
    [deposit] = book(ctx, %{"kind" => "deposit", "amount" => "100"})
    {:ok, lv, _html} = live(ctx.conn, ~p"/depot/transactions")

    lv |> element("#transaction-#{deposit.id} button") |> render_click()

    lv
    |> file_input("#transaction-form", :receipt, [
      %{name: "beleg.pdf", content: "%PDF-1.4\n%%EOF\n\n", type: "application/pdf"}
    ])
    |> render_upload("beleg.pdf", 50)

    confirm_click(lv, "#transaction-delete", "Diese Buchung löschen?")

    lv |> element("#depots-book") |> render_click()
    change(lv, %{kind: "deposit", amount: "5"}, "amount")
    lv |> form("#transaction-form") |> render_submit()

    assert render(lv) =~ "Buchung gespeichert."
    assert [%{amount: 500}] = Portfolios.list_transactions(ctx.scope)
  end

  test "creates a security by its ISIN in the form and selects it", ctx do
    FakeSymbolSearch.stub(fn _isin ->
      {:ok, [%{symbol: "IS3N.DE", name: "iShares Core MSCI EM IMI", exchange: "GER"}]}
    end)

    {:ok, lv, _html} = live(ctx.conn, ~p"/depot/transactions")
    lv |> element("#depots-book") |> render_click()
    lv |> element("#new-security") |> render_click()

    lv
    |> form("#transaction-form", security: %{isin: "IE00BKM4GZ67"})
    |> render_change(%{"_target" => ["security", "isin"]})

    refute_received {:search, _isin}
    assert has_element?(lv, "#new-security-panel", "Ist keine gültige ISIN")

    lv
    |> form("#transaction-form", security: %{isin: "IE00BKM4GZ66"})
    |> render_change(%{"_target" => ["security", "isin"]})

    render_async(lv)
    assert_received {:search, "IE00BKM4GZ66"}
    assert has_element?(lv, "#security_name[value='iShares Core MSCI EM IMI']")
    assert has_element?(lv, "#security_symbol[value='IS3N.DE']")

    lv
    |> form("#transaction-form", security: %{name: "iShares EM IMI"})
    |> render_change(%{"_target" => ["security", "name"]})

    lv |> form("#transaction-form") |> put_submitter("#new-security-create") |> render_submit()

    security = Repo.get_by!(Security, isin: "IE00BKM4GZ66")
    assert %{name: "iShares EM IMI", symbol: "IS3N.DE"} = security
    refute has_element?(lv, "#new-security-panel")
    assert has_element?(lv, "#transaction_security_id option[selected]", "iShares EM IMI")
  end

  test "„Buchen“ books while the panel of a new security is open", ctx do
    {:ok, lv, _html} = live(ctx.conn, ~p"/depot/transactions")
    lv |> element("#depots-book") |> render_click()
    lv |> element("#new-security") |> render_click()
    change(lv, %{kind: "deposit", amount: "5"}, "amount")

    lv
    |> form("#transaction-form")
    |> put_submitter("#transaction-form button[value=book]")
    |> render_submit()

    assert render(lv) =~ "Buchung gespeichert."
    assert [%{type: :deposit, amount: 500}] = Portfolios.list_transactions(ctx.scope)
    assert Repo.aggregate(Security, :count) == 1
  end

  test "says when Yahoo does not know the ISIN", ctx do
    FakeSymbolSearch.stub(fn _isin -> {:ok, []} end)

    {:ok, lv, _html} = live(ctx.conn, ~p"/depot/transactions")
    lv |> element("#depots-book") |> render_click()
    lv |> element("#new-security") |> render_click()

    lv
    |> form("#transaction-form", security: %{isin: "IE00BKM4GZ66"})
    |> render_change(%{"_target" => ["security", "isin"]})

    render_async(lv)

    assert has_element?(
             lv,
             "#security_isin-help[aria-live=polite]",
             "Yahoo kennt diese ISIN nicht."
           )
  end
end
