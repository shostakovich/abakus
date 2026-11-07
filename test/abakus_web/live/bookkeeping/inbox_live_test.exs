defmodule AbakusWeb.Bookkeeping.InboxLiveTest do
  use AbakusWeb.ConnCase

  import Phoenix.LiveViewTest
  import Abakus.DomainFixtures
  import AbakusWeb.PageText, only: [text: 2]

  alias Abakus.{Bookkeeping, FakePaperless, Paperless}
  alias Abakus.Bookkeeping.Attachments

  @url "http://paperless.test"

  setup :register_and_log_in_user

  setup %{scope: scope} do
    kontist = account_fixture(name: "Kontist", kind: :tracking)
    {:ok, _ids} = Bookkeeping.put_business_accounts(scope, [kontist.id])

    hosting =
      transaction_fixture(
        account_id: kontist.id,
        date: ~D[2026-10-05],
        amount: -2_368,
        payee_id: payee_fixture(name: "Hosting GmbH").id
      )

    license =
      transaction_fixture(
        account_id: kontist.id,
        date: ~D[2026-10-02],
        amount: -10_000,
        payee_id: payee_fixture(name: "Software Ltd").id
      )

    %{kontist: kontist, hosting: hosting, license: license}
  end

  defp choose(view, category, vat \\ nil) do
    params = %{"category" => category}
    params = if vat, do: Map.put(params, "vat", vat), else: params

    view
    |> form("#tax-lines-form", %{"sides" => %{"transaction" => params}})
    |> render_change()
  end

  defp save(view), do: view |> form("#tax-lines-form") |> render_submit()

  defp save_without_receipt(view),
    do: view |> form("#tax-lines-form", %{"no_receipt" => "true"}) |> render_submit()

  defp connect_paperless(c, documents) do
    FakePaperless.serve(%{@url => %{token: "t", documents: documents}})
    {:ok, _connection} = Paperless.update_connection(c.scope, %{"url" => @url, "token" => "t"})
  end

  defp open(view, transaction, payee) do
    view |> element("#inbox-#{transaction.id} button", payee) |> render_click()
    render_async(view)
  end

  defp attached(c, transaction),
    do: c.scope |> Attachments.list([transaction]) |> Map.values() |> List.flatten()

  test "works through the business transactions missing a category, one after another", c do
    {:ok, view, _html} = live(c.conn, ~p"/buchhaltung")

    assert has_element?(view, "#side-bookkeeping-inbox-sidebar[aria-current=page]", "Posteingang")
    assert has_element?(view, "header", "2 geschäftliche Buchungen ohne Kategorie oder Beleg.")
    assert has_element?(view, "#inbox-#{c.hosting.id}", "Kontist")
    assert has_element?(view, "#inbox-#{c.hosting.id}", "Kategorie und Beleg fehlen")

    view |> element("#inbox-#{c.hosting.id} button", "Hosting GmbH") |> render_click()
    assert has_element?(view, "#tax-lines-transaction", "Hosting GmbH")
    assert has_element?(view, "#tax-lines-save", "Speichern und weiter")

    choose(view, "internet")
    assert has_element?(view, "#tax-transaction-vat option[value='19'][selected]")
    assert text(view, "#tax-transaction-amounts") == "Netto −19,90 € · USt −3,78 €"

    save_without_receipt(view)
    refute has_element?(view, "#inbox-#{c.hosting.id}")
    assert has_element?(view, "#tax-lines-transaction", "Software Ltd")
    assert has_element?(view, "#tax-lines-save", "Speichern")
    refute has_element?(view, "#tax-lines-save", "weiter")

    choose(view, "licenses_13b_eu")
    assert has_element?(view, "#tax-transaction-vat option[value='reverse_charge'][selected]")
    assert text(view, "#tax-transaction-amounts") == "Netto −100,00 € · USt −19,00 €"

    save_without_receipt(view)
    refute has_element?(view, "#tax-lines-modal")
    assert has_element?(view, "#inbox-empty", "Alles zugeordnet")

    assert [%{category: "internet", vat: :rate_19}] =
             Map.values(Bookkeeping.tax_lines(c.scope, [c.hosting]))
  end

  test "shows what does not fit next to the field and keeps the transaction open", c do
    {:ok, view, _html} = live(c.conn, ~p"/buchhaltung")
    view |> element("#inbox-#{c.license.id} button", "Software Ltd") |> render_click()

    choose(view, "licenses")
    choose(view, "licenses", "reverse_charge")
    save(view)

    assert has_element?(view, "#tax-transaction-vat-error-0", "Passt nur zu einer §13b-Kategorie")
    assert has_element?(view, "#inbox-#{c.license.id}")
  end

  test "closing the dialog keeps the transaction in the inbox", c do
    {:ok, view, _html} = live(c.conn, ~p"/buchhaltung")
    view |> element("#inbox-#{c.license.id} button", "Software Ltd") |> render_click()

    render_hook(view, "close_tax_lines", %{})

    refute has_element?(view, "#tax-lines-modal")
    assert has_element?(view, "#inbox-#{c.license.id}")
  end

  test "keeps a transaction with its category until it has a receipt", c do
    {:ok, view, _html} = live(c.conn, ~p"/buchhaltung")
    open(view, c.hosting, "Hosting GmbH")

    choose(view, "internet")
    save(view)

    assert has_element?(view, "#inbox-#{c.hosting.id}", "Beleg fehlt")
    assert has_element?(view, "#tax-lines-transaction", "Software Ltd")
  end

  test "shows a receipt Paperless proposes beside the transaction and attaches it", c do
    connect_paperless(c, [
      FakePaperless.fixture(41, [],
        title: "Rechnung Oktober",
        content: "Hosting Oktober\nSumme 23,68 EUR",
        created: ~D[2026-10-01]
      ),
      FakePaperless.fixture(42, [], content: "Summe 99,00 EUR", created: ~D[2026-10-01])
    ])

    {:ok, view, _html} = live(c.conn, ~p"/buchhaltung")
    open(view, c.hosting, "Hosting GmbH")

    assert has_element?(view, "#proposal-41", "Rechnung Oktober")
    refute has_element?(view, "#proposal-42")
    assert has_element?(view, "#receipt-text", "Summe 23,68 EUR")
    assert has_element?(view, "#receipt-pdf[href='/buchhaltung/paperless/41'][target=_blank]")

    view |> element("#proposal-41-attach") |> render_click()

    assert [%{paperless_id: 41, title: "Rechnung Oktober"} = attachment] = attached(c, c.hosting)
    assert has_element?(view, "#receipt-#{attachment.id}", "Rechnung Oktober")
    refute has_element?(view, "#proposal-41")

    choose(view, "internet")
    save(view)

    refute has_element?(view, "#inbox-#{c.hosting.id}")
  end

  test "takes only a document id from the client", c do
    connect_paperless(c, [
      FakePaperless.fixture(41, [], content: "Summe 23,68 EUR", created: ~D[2026-10-01])
    ])

    {:ok, view, _html} = live(c.conn, ~p"/buchhaltung")
    open(view, c.hosting, "Hosting GmbH")

    view |> element("#proposal-41 button", "Dokument 41") |> render_click(%{"id" => "../tags"})
    assert has_element?(view, "#receipt-pdf[href='/buchhaltung/paperless/41']")

    view |> element("#proposal-41-attach") |> render_click(%{"id" => "41/../../tags"})
    assert attached(c, c.hosting) == []
    refute has_element?(view, "#receipts-error")
  end

  test "uploads a receipt to Paperless and attaches it", c do
    connect_paperless(c, [])
    {:ok, view, _html} = live(c.conn, ~p"/buchhaltung")
    open(view, c.license, "Software Ltd")
    assert has_element?(view, "#receipts-no-proposals")

    receipt =
      file_input(view, "#receipts-upload", :receipt, [
        %{name: "Lizenz.pdf", content: "%PDF-1.4 Lizenz", type: "application/pdf"}
      ])

    render_upload(receipt, "Lizenz.pdf")
    render_async(view)

    assert [%{title: "Lizenz", paperless_id: id} = attachment] = attached(c, c.license)
    assert [%{pdf: "%PDF-1.4 Lizenz"}] = FakePaperless.documents(@url)
    assert has_element?(view, "#receipt-#{attachment.id}", "Lizenz")
    assert has_element?(view, "#receipt-pdf[href='/buchhaltung/paperless/#{id}']")

    view |> element("#receipt-#{attachment.id}-detach") |> render_click()
    assert attached(c, c.license) == []
    refute has_element?(view, "#receipt-#{attachment.id}")
  end

  test "an upload still running when the dialog moves on stays with its own transaction", c do
    FakePaperless.serve(%{@url => %{token: "t", documents: [], upload_gate: self()}})
    {:ok, _connection} = Paperless.update_connection(c.scope, %{"url" => @url, "token" => "t"})
    {:ok, view, _html} = live(c.conn, ~p"/buchhaltung")
    open(view, c.license, "Software Ltd")

    view
    |> file_input("#receipts-upload", :receipt, [
      %{name: "Lizenz.pdf", content: "%PDF-1.4 Lizenz", type: "application/pdf"}
    ])
    |> render_upload("Lizenz.pdf")

    assert_receive {:uploading, uploader}
    assert has_element?(view, "#receipts-upload", "Wird an Paperless übergeben")

    view |> element("#inbox-#{c.hosting.id} button", "Hosting GmbH") |> render_click()
    assert has_element?(view, "#receipts-upload", "Hochladen")

    send(uploader, :go)
    render_async(view)

    assert [%{title: "Lizenz"}] = attached(c, c.license)
    assert attached(c, c.hosting) == []
    refute has_element?(view, "#receipt-shown")
    assert has_element?(view, "#receipts-upload", "Hochladen")
  end

  test "tells a rejected token and a file too large for Paperless", c do
    FakePaperless.serve(%{
      @url => %{token: "t", documents: [], uploads_fail: {:http_status, 413}}
    })

    {:ok, _connection} =
      Paperless.update_connection(c.scope, %{"url" => @url, "token" => "falsch"})

    {:ok, view, _html} = live(c.conn, ~p"/buchhaltung")
    open(view, c.license, "Software Ltd")
    assert has_element?(view, "#receipts-error", "Paperless hat den API-Token abgelehnt.")

    {:ok, _connection} = Paperless.update_connection(c.scope, %{"url" => @url, "token" => "t"})
    {:ok, view, _html} = live(c.conn, ~p"/buchhaltung")
    open(view, c.license, "Software Ltd")

    view
    |> file_input("#receipts-upload", :receipt, [
      %{name: "Lizenz.pdf", content: "%PDF-1.4 Lizenz", type: "application/pdf"}
    ])
    |> render_upload("Lizenz.pdf")

    render_async(view)
    assert has_element?(view, "#receipts-error", "Die Datei ist zu groß für Paperless.")
  end

  test "points to the settings without Paperless", c do
    {:ok, view, _html} = live(c.conn, ~p"/buchhaltung")
    open(view, c.hosting, "Hosting GmbH")

    assert has_element?(view, "#receipts-not-connected a[href='/settings/paperless']")
    refute has_element?(view, "#receipts-upload")
  end

  test "tells when Paperless cannot be reached", c do
    {:ok, _connection} =
      Paperless.update_connection(c.scope, %{"url" => "http://weg.test", "token" => "t"})

    FakePaperless.serve(%{})
    {:ok, view, _html} = live(c.conn, ~p"/buchhaltung")
    open(view, c.hosting, "Hosting GmbH")

    assert has_element?(view, "#receipts-error", "Paperless ist gerade nicht erreichbar.")
  end
end
