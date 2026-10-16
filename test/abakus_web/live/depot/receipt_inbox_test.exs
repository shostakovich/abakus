defmodule AbakusWeb.Depot.ReceiptInboxTest do
  use AbakusWeb.ConnCase

  import Phoenix.LiveViewTest
  import Abakus.Depot.{PortfoliosFixtures, ReceiptsFixtures, SecuritiesFixtures}

  alias Abakus.Depot.{
    FakeModel,
    FakePaperless,
    FakeSymbolSearch,
    FakeTextExtractor,
    Portfolios,
    Receipts,
    Settings
  }

  alias Abakus.Depot.Portfolios.Receipt
  alias Abakus.Repo

  # The model's failures are logged.
  @moduletag :capture_log

  setup :register_and_log_in_user

  setup %{scope: scope} do
    account = account_fixture(scope, name: "Verrechnungskonto")

    portfolio =
      portfolio_fixture(scope,
        name: "Sparplan",
        reference_account_id: account.id,
        depot_number: "44 72"
      )

    portfolio_fixture(scope, name: "Langfristig")
    security = security_fixture(name: "Vanguard FTSE All-World", isin: "IE00BK5BQT80")
    FakeTextExtractor.stub(receipt_text())
    %{account: account, portfolio: portfolio, security: security}
  end

  defp upload(lv, files) do
    entries =
      for {name, content} <- files,
          do: %{name: name, content: content, type: "application/pdf"}

    input = file_input(lv, "#receipts-upload", :receipts, entries)
    for {name, _content} <- files, do: render_upload(input, name)
    lv
  end

  defp pdf(id \\ System.unique_integer()), do: "%PDF-1.4\n% #{id}\n%%EOF\n"

  # Uploads PDFs on „Buchungen“ and waits until the model has read them.
  defp upload_and_recognise(conn, files \\ [{"beleg.pdf", pdf()}]) do
    {:ok, lv, _html} = live(conn, ~p"/depot/transactions")
    upload(lv, files)
    await_recognition()
    lv
  end

  defp only_receipt(scope), do: hd(Receipts.list_inbox(scope))

  # „Buchungen“ in the sidebar counts nothing, neither as a number nor in its name.
  defp refute_inbox_count(lv) do
    refute has_element?(lv, sidebar_link("/depot/transactions") <> " .tabular-nums")
    refute has_element?(lv, sidebar_link("/depot/transactions") <> "[aria-label]")
  end

  test "an uploaded PDF goes through the model into the inbox and is booked once confirmed",
       ctx do
    FakeModel.stub(fn _text -> {:ok, answer()} end)
    lv = upload_and_recognise(ctx.conn)
    receipt = only_receipt(ctx.scope)

    row = lv |> element("#receipt-#{receipt.id}") |> render()
    assert row =~ "Kauf\u2060\u00A0· Vanguard FTSE All-World"

    assert row =~
             "01.10.2026\u2060\u00A0· 93,207 Stück\u2060\u00A0· 1.125,00\u00A0€\u2060\u00A0· Upload"

    assert has_element?(lv, "#receipt-#{receipt.id}-status", "Geprüft")
    assert has_element?(lv, sidebar_link("/depot/transactions"), "1")

    lv |> element("#receipt-#{receipt.id} button", "Prüfen und buchen") |> render_click()

    assert has_element?(lv, "#transaction-modal h2", "Beleg prüfen")
    assert has_element?(lv, "#transaction-modal", "beleg.pdf\u2060\u00A0· Kauf vom 01.10.2026")
    assert has_element?(lv, "#receipt-check-amount", "Stück × Kurs = 1.125,00 €")
    assert has_element?(lv, "#receipt-check-isin", "ISIN gültig und bekannt")
    assert has_element?(lv, "#receipt-check-depot", "Depot …4472 gehört zu „Sparplan“")
    assert has_element?(lv, "#receipt-check-reference", "Referenz SP-0001 noch nicht gebucht")
    assert has_element?(lv, "#receipt-text mark", "93,207")
    assert has_element?(lv, "#receipt-pdf[href='/depot/receipts/#{receipt.id}']")
    assert has_element?(lv, "#transaction_shares[value='93,207']")
    assert has_element?(lv, "#transaction_price[value='12,0699']")
    assert has_element?(lv, "#transaction_amount[value='1.125,00']")
    refute has_element?(lv, "#receipt-checks [data-problem]")
    assert has_element?(lv, "#transaction-book", "Buchen")
    refute has_element?(lv, "#new-security")
    refute has_element?(lv, "input[name='transaction[kind]'][value=deposit]")
    assert has_element?(lv, "#transaction_security_id option[selected]", "Vanguard")
    assert has_element?(lv, "#transaction_portfolio_id option[selected]", "Sparplan")
    assert has_element?(lv, "#transaction_account_id option[selected]", "Verrechnungskonto")
    refute has_element?(lv, "#transaction-form input[type=file]")

    lv |> form("#transaction-form") |> render_submit()

    assert render(lv) =~ "Buchung gespeichert."
    refute has_element?(lv, "#transaction-modal")
    refute has_element?(lv, "#inbox")
    refute_inbox_count(lv)

    assert [transaction] = Portfolios.list_transactions(ctx.scope)

    assert %{type: :buy, source: :receipt, amount: 112_500, receipt_id: receipt_id} =
             transaction

    assert transaction.account_id == ctx.account.id
    assert receipt_id == receipt.id
    assert Repo.get!(Receipt, receipt.id).status == :booked
    assert has_element?(lv, "#transaction-#{transaction.id}-receipt")
  end

  test "shows „wird erkannt“ until the model is done and updates every open page", ctx do
    test = self()

    FakeModel.stub(fn _text ->
      send(test, {:waiting, self()})
      receive do: (:go -> {:ok, answer()})
    end)

    {:ok, other, _html} = live(ctx.conn, ~p"/depot")
    {:ok, lv, _html} = live(ctx.conn, ~p"/depot/transactions")
    upload(lv, [{"beleg.pdf", pdf()}])
    assert_receive {:waiting, task}

    assert has_element?(lv, "#inbox [id$=-status]", "Wird erkannt")
    refute has_element?(lv, "#inbox button")
    refute_inbox_count(other)

    send(task, :go)
    await_recognition()
    assert has_element?(lv, "#inbox button", "Prüfen und buchen")
    assert has_element?(other, sidebar_link("/depot/transactions"), "1")
  end

  test "Scenario: Unknown depot number — the user picks the portfolio before booking", ctx do
    FakeTextExtractor.stub(String.replace(receipt_text(), "Depot 4472", "Depot 0815 9999"))
    FakeModel.stub(fn _text -> {:ok, answer(%{"depot_number" => "0815 9999"})} end)
    lv = upload_and_recognise(ctx.conn)
    receipt = only_receipt(ctx.scope)

    assert has_element?(
             lv,
             "#receipt-#{receipt.id}-warning",
             "Depot …9999 gehört zu keinem deiner Depots. Bitte Depot wählen."
           )

    assert has_element?(lv, "#receipt-#{receipt.id}-status", "Bitte prüfen")
    assert has_element?(lv, sidebar_link("/depot/transactions"), "1")

    lv |> element("#receipt-#{receipt.id} button", "Prüfen und buchen") |> render_click()

    assert has_element?(
             lv,
             "#receipt-check-depot[data-problem]",
             "Depot …9999 gehört zu keinem deiner Depots"
           )

    refute has_element?(lv, "#transaction_portfolio_id option[selected]")
    assert has_element?(lv, "#receipt-checks [data-problem]")

    assert has_element?(
             lv,
             "#transaction_portfolio_id[aria-describedby~='transaction_portfolio_id-help']"
           )

    assert has_element?(lv, "#transaction_portfolio_id-help", "Laut Beleg Depot …9999")

    lv |> form("#transaction-form") |> render_submit()
    assert has_element?(lv, "#transaction-modal")
    assert Portfolios.list_transactions(ctx.scope) == []

    lv
    |> form("#transaction-form", transaction: %{portfolio_id: ctx.portfolio.id})
    |> render_change(%{"_target" => ["transaction", "portfolio_id"]})

    refute has_element?(lv, "#transaction_portfolio_id-help")
    lv |> form("#transaction-form") |> render_submit()

    assert render(lv) =~ "Buchung gespeichert."
    assert [%{portfolio_id: portfolio_id}] = Portfolios.list_transactions(ctx.scope)
    assert portfolio_id == ctx.portfolio.id
  end

  test "a depot number entered later passes the check of the receipts in the inbox", ctx do
    FakeTextExtractor.stub(String.replace(receipt_text(), "Depot 4472", "Depot 0815 9999"))
    FakeModel.stub(fn _text -> {:ok, answer(%{"depot_number" => "0815 9999"})} end)
    lv = upload_and_recognise(ctx.conn)
    receipt = only_receipt(ctx.scope)
    langfristig = Enum.find(Portfolios.list_portfolios(ctx.scope), &(&1.name == "Langfristig"))

    {:ok, portfolios_page, _html} = live(ctx.conn, ~p"/depot/portfolios")
    portfolios_page |> element("#depot-number-#{langfristig.id} button") |> render_click()

    portfolios_page
    |> form("#depot-number-form", portfolio: %{depot_number: "08159999"})
    |> render_submit()

    assert has_element?(lv, "#receipt-#{receipt.id}-status", "Geprüft")
  end

  test "a receipt from Paperless names its document, and the inbox when Paperless was polled",
       ctx do
    FakeModel.stub(fn _text -> {:ok, answer()} end)
    url = "http://paperless.test"

    FakePaperless.serve(%{
      url => %{token: "t", documents: [FakePaperless.document(4812, ["zf"])]}
    })

    {:ok, setting} =
      Settings.update_paperless(ctx.scope, %{
        "paperless_url" => url,
        "paperless_token" => "t",
        "paperless_tag" => "zf"
      })

    {:ok, lv, _html} = live(ctx.conn, ~p"/depot/transactions")
    Receipts.poll_paperless(setting)
    await_recognition()
    receipt = only_receipt(ctx.scope)

    assert has_element?(
             lv,
             "#receipt-#{receipt.id}",
             "93,207 Stück\u2060\u00A0· 1.125,00\u00A0€\u2060\u00A0· Paperless #4812"
           )

    assert has_element?(lv, "#receipt-#{receipt.id}-status", "Geprüft")

    assert has_element?(lv, "#inbox-polled", "zuletzt abgefragt")

    lv |> element("#receipt-#{receipt.id} button", "Prüfen und buchen") |> render_click()

    assert has_element?(
             lv,
             "#transaction-modal",
             "Paperless #4812\u2060\u00A0· Kauf vom 01.10.2026"
           )
  end

  test "a model answer off the schema leaves the receipt in the inbox with an empty form", ctx do
    FakeModel.stub(fn _text -> {:ok, ~s({"kind": "purchase", "shares": 93.207})} end)
    lv = upload_and_recognise(ctx.conn)
    receipt = only_receipt(ctx.scope)

    assert has_element?(lv, "#receipt-#{receipt.id}", "beleg.pdf")
    assert has_element?(lv, "#receipt-#{receipt.id}-status", "Nicht erkannt")
    assert has_element?(lv, "#receipt-#{receipt.id}", "bitte von Hand erfassen")

    lv |> element("#receipt-#{receipt.id} button", "Erfassen") |> render_click()

    assert has_element?(lv, "#transaction-modal h2", "Beleg prüfen")
    assert has_element?(lv, "#receipt-checks", "Nicht erkannt.")
    assert has_element?(lv, "#receipt-text", "Wertpapierabrechnung Kauf")
    assert has_element?(lv, "#transaction_shares:not([value])")
    refute has_element?(lv, "#transaction-form [aria-invalid]")
  end

  test "Scenario: A duplicate by bank reference — marked as booked and offered to discard", ctx do
    FakeModel.stub(fn _text -> {:ok, answer(%{"bank_reference" => "SP-0001"})} end)
    lv = upload_and_recognise(ctx.conn)
    first = only_receipt(ctx.scope)
    lv |> element("#receipt-#{first.id} button") |> render_click()

    lv
    |> form("#transaction-form", transaction: %{portfolio_id: ctx.portfolio.id})
    |> render_submit()

    upload(lv, [{"beleg-2.pdf", pdf()}])
    await_recognition()
    second = only_receipt(ctx.scope)

    assert has_element?(
             lv,
             "#receipt-#{second.id}",
             "gleiche Referenznummer wie die Buchung vom 01.10.2026"
           )

    assert has_element?(lv, "#receipt-#{second.id}-status", "Doppelt")
    refute has_element?(lv, "#receipt-#{second.id} button", "Prüfen und buchen")

    lv |> element("#receipt-#{second.id} button", "Verwerfen") |> render_click()

    refute has_element?(lv, "#inbox")
    assert Repo.get!(Receipt, second.id).status == :discarded
  end

  test "deleting the booked transaction clears the duplicate mark of another receipt", ctx do
    FakeModel.stub(fn _text -> {:ok, answer()} end)
    lv = upload_and_recognise(ctx.conn, [{"a.pdf", pdf()}, {"b.pdf", pdf()}])
    [second, first] = Receipts.list_inbox(ctx.scope)
    lv |> element("#receipt-#{first.id} button") |> render_click()
    lv |> form("#transaction-form") |> render_submit()
    assert has_element?(lv, "#receipt-#{second.id}", "gleiche Referenznummer")

    [transaction] = Portfolios.list_transactions(ctx.scope)
    lv |> element("#transaction-#{transaction.id} button") |> render_click()
    confirm_click(lv, "#transaction-delete", "Diese Buchung löschen?")

    assert render(lv) =~ "Buchung gelöscht."
    assert has_element?(lv, "#receipt-#{second.id}-status", "Geprüft")
  end

  test "attaching a waiting file in the plain dialog takes it out of every open inbox", ctx do
    FakeModel.stub(fn _text -> {:ok, answer()} end)
    content = pdf()
    lv = upload_and_recognise(ctx.conn, [{"beleg.pdf", content}])
    {:ok, other, _html} = live(ctx.conn, ~p"/depot/transactions")
    assert has_element?(other, "#inbox")

    lv |> element("#transactions-book") |> render_click()

    lv
    |> form("#transaction-form",
      transaction: %{kind: "deposit", account_id: ctx.account.id, amount: "5"}
    )
    |> render_change(%{"_target" => ["transaction", "amount"]})

    lv
    |> file_input("#transaction-form", :receipt, [
      %{name: "beleg.pdf", content: content, type: "application/pdf"}
    ])
    |> render_upload("beleg.pdf")

    lv |> form("#transaction-form") |> render_submit()

    assert render(lv) =~ "Buchung gespeichert."
    refute has_element?(other, "#inbox")
  end

  test "a security created in „Beleg prüfen“ passes the receipt's check in the inbox", ctx do
    FakeSymbolSearch.stub(fn _query -> {:ok, []} end)
    FakeTextExtractor.stub(String.replace(receipt_text(), "IE00BK5BQT80", "US0378331005"))

    FakeModel.stub(fn _text ->
      {:ok, answer(%{"isin" => "US0378331005", "security_name" => "Apple Inc."})}
    end)

    lv = upload_and_recognise(ctx.conn)
    receipt = only_receipt(ctx.scope)
    assert has_element?(lv, "#receipt-#{receipt.id}", "Wertpapier noch nicht angelegt")

    lv |> element("#inbox button", "Prüfen und buchen") |> render_click()
    lv |> form("#transaction-form") |> put_submitter("#new-security-create") |> render_submit()
    close_modal(lv, "#receipt-later", "transaction-modal")

    refute has_element?(lv, "#receipt-#{receipt.id}", "Wertpapier noch nicht angelegt")
  end

  test "Scenario: The same file twice — no second inbox item appears", ctx do
    content = pdf()
    lv = upload_and_recognise(ctx.conn, [{"beleg.pdf", content}])

    upload(lv, [{"nochmal.pdf", content}])

    assert render(lv) =~ "nochmal.pdf liegt schon im Eingang."
    assert [_one] = Receipts.list_inbox(ctx.scope)
    assert has_element?(lv, "#inbox-title span", ~r/^\s*1\s*$/)
  end

  test "takes several PDFs at once", ctx do
    lv = upload_and_recognise(ctx.conn, [{"a.pdf", pdf()}, {"b.pdf", pdf()}])

    assert has_element?(lv, "#inbox-title span", ~r/^\s*2\s*$/)
    assert has_element?(lv, sidebar_link("/depot/transactions"), "2")
    assert render(lv) =~ "2 Belege liegen im Eingang."
  end

  test "sums up several PDFs in one message", ctx do
    content = pdf()
    lv = upload_and_recognise(ctx.conn, [{"beleg.pdf", content}])

    upload(lv, [{"nochmal.pdf", content}, {"neu.pdf", pdf()}, {"kaputt.pdf", "kein PDF"}])

    assert render(lv) =~
             "kaputt.pdf ist keine PDF-Datei. neu.pdf liegt im Eingang. " <>
               "nochmal.pdf liegt schon im Eingang."
  end

  test "refuses a file that is no PDF", ctx do
    {:ok, lv, _html} = live(ctx.conn, ~p"/depot/transactions")
    upload(lv, [{"beleg.pdf", "kein PDF"}])

    assert render(lv) =~ "beleg.pdf ist keine PDF-Datei."
    assert Receipts.list_inbox(ctx.scope) == []
  end

  test "says once that a file is no PDF and drops it, so the next upload goes through", ctx do
    FakeModel.stub(fn _text -> {:ok, answer()} end)
    {:ok, lv, _html} = live(ctx.conn, ~p"/depot/transactions")

    input =
      file_input(lv, "#receipts-upload", :receipts, [
        %{name: "notiz.txt", content: "Notiz", type: "text/plain"}
      ])

    assert lv |> form("#receipts-upload") |> render_change(input) =~
             "Bitte nur PDF-Dateien wählen."

    assert lv |> element("#receipts-upload") |> render() =~ ~s(data-phx-active-refs="")

    upload(lv, [{"beleg.pdf", pdf()}])
    await_recognition()

    assert render(lv) =~ "beleg.pdf liegt im Eingang."
    assert [_receipt] = Receipts.list_inbox(ctx.scope)
  end

  test "an unsupported receipt says so and can be discarded", ctx do
    FakeModel.stub(fn _text -> {:ok, answer(%{"kind" => "other"})} end)
    lv = upload_and_recognise(ctx.conn)
    receipt = only_receipt(ctx.scope)

    assert has_element?(lv, "#receipt-#{receipt.id}-status", "Nicht unterstützt")
    lv |> element("#receipt-#{receipt.id} button", "Verwerfen") |> render_click()

    assert render(lv) =~ "Beleg verworfen."
    refute has_element?(lv, "#inbox")
  end

  test "a failed check shows in the row and the dialog", ctx do
    FakeModel.stub(fn _text -> {:ok, answer(%{"amount" => 375.0, "shares" => 31.07})} end)
    lv = upload_and_recognise(ctx.conn)
    receipt = only_receipt(ctx.scope)

    assert has_element?(
             lv,
             "#receipt-#{receipt.id}-warning",
             "Stück × Kurs ergibt 375,01 €, der Beleg nennt 375,00 €. Bitte Kurs prüfen."
           )

    lv |> element("#receipt-#{receipt.id} button", "Korrigieren") |> render_click()

    assert has_element?(
             lv,
             "#receipt-check-amount[data-problem]",
             "der Beleg nennt 375,00"
           )

    assert has_element?(lv, "#transaction-book", "Buchen")
    assert has_element?(lv, "#transaction_price[aria-describedby~='transaction_price-help']")
    assert has_element?(lv, "#transaction_price-help", "Summe laut Beleg: 375,00")
    assert has_element?(lv, "#transaction_amount-help", "Stück × Kurs ergibt 375,01")
  end

  test "a value not in the receipt fails its check in the row and the dialog", ctx do
    FakeModel.stub(fn _text -> {:ok, answer(%{"date" => "2026-10-02"})} end)
    lv = upload_and_recognise(ctx.conn)
    receipt = only_receipt(ctx.scope)

    assert has_element?(
             lv,
             "#receipt-#{receipt.id}-warning",
             "Datum 02.10.2026 steht nicht im Beleg, bitte prüfen."
           )

    lv |> element("#receipt-#{receipt.id} button", "Korrigieren") |> render_click()

    assert has_element?(
             lv,
             "#receipt-check-found[data-problem]",
             "Datum 02.10.2026 steht nicht im Beleg"
           )

    refute has_element?(lv, "#receipt-check-amount[data-problem]")
  end

  test "a receipt whose values all stand in it says so", ctx do
    FakeModel.stub(fn _text -> {:ok, answer()} end)
    lv = upload_and_recognise(ctx.conn)
    lv |> element("#inbox button", "Prüfen und buchen") |> render_click()

    assert has_element?(
             lv,
             "#receipt-check-found:not([data-problem])",
             "Alle Werte im Beleg gefunden"
           )
  end

  test "an unknown ISIN opens „Neues Wertpapier“ with it", ctx do
    FakeSymbolSearch.stub(fn _query -> {:ok, []} end)

    FakeTextExtractor.stub(String.replace(receipt_text(), "IE00BK5BQT80", "US0378331005"))

    FakeModel.stub(fn _text ->
      {:ok, answer(%{"isin" => "US0378331005", "security_name" => "Apple Inc."})}
    end)

    lv = upload_and_recognise(ctx.conn)
    lv |> element("#inbox button", "Prüfen und buchen") |> render_click()

    assert has_element?(lv, "#receipt-check-isin", "Wertpapier noch nicht angelegt")
    assert has_element?(lv, "#new-security-panel #security_isin[value='US0378331005']")
    assert has_element?(lv, "#new-security-panel #security_name[value='Apple Inc.']")
  end

  test "the dialog discards the receipt or leaves it for later", ctx do
    FakeModel.stub(fn _text -> {:ok, answer()} end)
    lv = upload_and_recognise(ctx.conn)
    receipt = only_receipt(ctx.scope)

    lv |> element("#inbox button", "Prüfen und buchen") |> render_click()
    close_modal(lv, "#receipt-later", "transaction-modal")

    refute has_element?(lv, "#transaction-modal")
    assert has_element?(lv, "#receipt-#{receipt.id}")

    lv |> element("#inbox button", "Prüfen und buchen") |> render_click()
    lv |> element("#receipt-discard") |> render_click()

    assert render(lv) =~ "Beleg verworfen."
    refute has_element?(lv, "#inbox")
    assert Portfolios.list_transactions(ctx.scope) == []
  end

  test "discarding a receipt that has left the inbox says so", ctx do
    FakeModel.stub(fn _text -> {:ok, answer()} end)
    lv = upload_and_recognise(ctx.conn)
    receipt = only_receipt(ctx.scope)

    lv |> element("#inbox button", "Prüfen und buchen") |> render_click()
    :ok = Receipts.discard(ctx.scope, receipt.id)
    lv |> element("#receipt-discard") |> render_click()

    assert render(lv) =~ "Dieser Beleg liegt nicht mehr im Eingang."
    refute render(lv) =~ "Beleg verworfen."

    render_click(lv, "discard", %{id: receipt.id})
    assert render(lv) =~ "Dieser Beleg liegt nicht mehr im Eingang."
  end

  test "a submit or discard after the receipt left the dialog only closes it", ctx do
    FakeModel.stub(fn _text -> {:ok, answer()} end)
    lv = upload_and_recognise(ctx.conn)
    receipt = only_receipt(ctx.scope)
    lv |> element("#inbox button", "Prüfen und buchen") |> render_click()
    params = %{"receipt_id" => to_string(receipt.id), "transaction" => %{"kind" => "deposit"}}
    close_modal(lv, "#receipt-later", "transaction-modal")

    dialog = with_target(lv, "#transaction-dialog")
    render_submit(dialog, "book", params)
    render_click(dialog, "discard_receipt", %{})

    lv |> element("#transactions-book") |> render_click()
    render_submit(dialog, "book", params)

    refute has_element?(lv, "#transaction-modal")
    assert Portfolios.list_transactions(ctx.scope) == []
    assert [%Receipt{status: :ready}] = Receipts.list_inbox(ctx.scope)
  end

  test "a receipt that no longer waits is not opened", ctx do
    FakeModel.stub(fn _text -> {:ok, answer()} end)
    lv = upload_and_recognise(ctx.conn)
    receipt = only_receipt(ctx.scope)
    :ok = Receipts.discard(ctx.scope, receipt.id)

    lv |> with_target("#transaction-dialog") |> render_click("open_receipt", %{id: receipt.id})

    assert render(lv) =~ "Dieser Beleg liegt nicht mehr im Eingang."
    refute has_element?(lv, "#transaction-modal")
  end
end
