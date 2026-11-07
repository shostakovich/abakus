defmodule AbakusWeb.RegisterBookkeepingTest do
  use AbakusWeb.ConnCase

  import Phoenix.LiveViewTest
  import Abakus.DomainFixtures
  import Abakus.BookkeepingFixtures
  import AbakusWeb.PageText, only: [text: 2]

  alias Abakus.{Bookkeeping, FakePaperless, Ledger, Paperless}
  alias Abakus.Bookkeeping.{Attachments, FakeElster, Filings}

  @url "http://paperless.test"

  setup :register_and_log_in_user

  setup %{scope: scope} do
    giro = account_fixture(name: "Girokonto")
    kontist = account_fixture(name: "Kontist", kind: :tracking)
    payee = payee_fixture(name: "Buchhandlung")

    book =
      transaction_fixture(
        account_id: giro.id,
        date: ~D[2026-10-05],
        amount: -3_210,
        payee_id: payee.id,
        category_id: category_fixture(name: "Bücher").id
      )

    %{scope: scope, giro: giro, kontist: kontist, book: book}
  end

  defp keep_books(c), do: Bookkeeping.put_business_accounts(c.scope, [c.kontist.id])

  test "has no Buchhaltung column for a user who keeps no books", c do
    {:ok, view, _html} = live(c.conn, ~p"/budget/accounts/#{c.giro}")

    refute has_element?(view, "#register-table th", "Buchhaltung")
    refute has_element?(view, "#tx-#{c.book.id}-tax")
  end

  test "gives a business expense on a private account its category in its own column", c do
    keep_books(c)
    {:ok, view, _html} = live(c.conn, ~p"/budget/accounts/#{c.giro}")

    assert has_element?(view, "#register-table th", "Buchhaltung")
    assert has_element?(view, "#tx-#{c.book.id}-tax[aria-label='Buchhaltung bearbeiten']")

    view |> element("#tx-#{c.book.id}-tax") |> render_click()
    assert has_element?(view, "#tax-lines-save", "Speichern")

    view
    |> form("#tax-lines-form", %{"sides" => %{"transaction" => %{"category" => "books"}}})
    |> render_change()

    view |> form("#tax-lines-form") |> render_submit()

    refute has_element?(view, "#tax-lines-modal")
    assert text(view, "#tx-#{c.book.id}-tax") == "Zeitschriften/Bücher"
    assert has_element?(view, "#tx-#{c.book.id}-tax[title='7 %']")
    assert has_element?(view, "#tx-card-#{c.book.id}", "Zeitschriften/Bücher")
  end

  test "refuses to change the VAT rate of a transaction in a sent quarter", c do
    keep_books(c)
    fix_today(~D[2027-04-15])

    licence =
      transaction_fixture(account_id: c.kontist.id, date: ~D[2027-02-10], amount: -11_900)

    {:ok, _lines} =
      Bookkeeping.save_tax_lines(c.scope, Bookkeeping.get_transaction(c.scope, licence.id), %{
        "transaction" => %{"category" => "office_supplies", "vat" => "19"}
      })

    elster_fixture(c.scope)
    FakeElster.serve()
    {:ok, _filing} = Filings.send_vat_quarter(c.scope, 2027, 1, "4711")

    {:ok, view, _html} = live(c.conn, ~p"/budget/accounts/#{c.kontist}")
    view |> element("#tx-#{licence.id}-tax") |> render_click()

    view
    |> form("#tax-lines-form", %{"sides" => %{"transaction" => %{"vat" => "7"}}})
    |> render_submit()

    assert text(view, "#tax-lines-locked p") == "Zeitraum ist festgeschrieben"
    assert has_element?(view, "#tax-transaction-vat option[value='19'][selected]")

    render_click(view, "close_tax_lines", %{})
    assert has_element?(view, "#tx-#{licence.id}-tax[title='19 %']")
  end

  test "annotates a split per part and a transfer not at all", c do
    keep_books(c)

    {:ok, split} =
      Ledger.create_transaction(c.scope, %{
        account_id: c.kontist.id,
        date: ~D[2026-10-06],
        amount: -1_500,
        subtransactions: [%{amount: -1_000}, %{amount: -500}]
      })

    {:ok, transfer} =
      Ledger.create_transaction(c.scope, %{
        account_id: c.kontist.id,
        date: ~D[2026-10-07],
        amount: -50_000,
        payee_id: c.giro.transfer_payee.id,
        counterpart_category_id: Abakus.Categories.ready_to_assign!(c.scope).id
      })

    {:ok, view, _html} = live(c.conn, ~p"/budget/accounts/#{c.kontist}")

    refute has_element?(view, "#tx-#{split.id}-tax")
    refute has_element?(view, "#tx-#{transfer.id}-tax")

    view |> element("#tx-#{split.id}-part-1-tax") |> render_click()
    [first, second] = Bookkeeping.get_transaction(c.scope, split.id).subtransactions

    view
    |> form("#tax-lines-form", %{
      "sides" => %{
        first.id => %{"category" => "internet"},
        second.id => %{"category" => "bank_fees"}
      }
    })
    |> render_change()

    view |> form("#tax-lines-form") |> render_submit()

    assert text(view, "#tx-#{split.id}-part-0-tax") == "Internet"
    assert text(view, "#tx-#{split.id}-part-1-tax") == "Nebenkosten des Geldverkehrs"
  end

  test "shows a paperclip per receipt that opens its PDF, a split's own on its row", c do
    keep_books(c)

    FakePaperless.serve(%{
      @url => %{
        token: "t",
        documents: [
          FakePaperless.fixture(1, [], title: "Quittung"),
          FakePaperless.fixture(2, [], title: "Rechnung")
        ]
      }
    })

    {:ok, _connection} = Paperless.update_connection(c.scope, %{"url" => @url, "token" => "t"})

    {:ok, split} =
      Ledger.create_transaction(c.scope, %{
        account_id: c.giro.id,
        date: ~D[2026-10-06],
        amount: -1_500,
        subtransactions: [%{amount: -1_000}, %{amount: -500}]
      })

    split = Bookkeeping.get_transaction(c.scope, split.id)
    [first, _second] = split.subtransactions
    {:ok, _attachment} = Attachments.attach(c.scope, c.book, nil, 1)
    {:ok, _attachment} = Attachments.attach(c.scope, c.book, nil, 2)
    {:ok, _attachment} = Attachments.attach(c.scope, split, nil, 2)
    {:ok, _attachment} = Attachments.attach(c.scope, split, first.id, 1)

    {:ok, view, _html} = live(c.conn, ~p"/budget/accounts/#{c.giro}")

    assert has_element?(
             view,
             "a#tx-#{c.book.id}-tax-receipt-0[href='/buchhaltung/paperless/1'][target=_blank][title=Quittung]"
           )

    assert has_element?(view, "a#tx-#{c.book.id}-tax-receipt-1[href='/buchhaltung/paperless/2']")
    assert has_element?(view, "#tx-#{split.id}-tax-receipt-0[href='/buchhaltung/paperless/2']")

    assert has_element?(
             view,
             "#tx-#{split.id}-part-0-tax-receipt-0[href='/buchhaltung/paperless/1']"
           )

    refute has_element?(view, "#tx-#{split.id}-part-1-tax-receipt-0")
    assert has_element?(view, "#tx-card-#{c.book.id}", "2 Belege")
  end

  test "attaches a receipt to one part of a split", c do
    keep_books(c)

    FakePaperless.serve(%{
      @url => %{
        token: "t",
        documents: [FakePaperless.fixture(3, [], content: "Summe 15,00", created: ~D[2026-10-06])]
      }
    })

    {:ok, _connection} = Paperless.update_connection(c.scope, %{"url" => @url, "token" => "t"})

    {:ok, split} =
      Ledger.create_transaction(c.scope, %{
        account_id: c.kontist.id,
        date: ~D[2026-10-06],
        amount: -1_500,
        subtransactions: [%{amount: -1_000, memo: "Server"}, %{amount: -500, memo: "Domain"}]
      })

    {:ok, view, _html} = live(c.conn, ~p"/budget/accounts/#{c.kontist}")
    view |> element("#tx-#{split.id}-part-1-tax") |> render_click()
    render_async(view)

    assert has_element?(view, "#receipts-side option", "Ganze Buchung")
    [_server, domain] = Bookkeeping.get_transaction(c.scope, split.id).subtransactions
    view |> form("#receipts-side-form", %{"side" => domain.id}) |> render_change()
    view |> element("#proposal-3-attach") |> render_click()

    assert [%{subtransaction_id: part_id}] =
             c.scope
             |> Attachments.list([Bookkeeping.get_transaction(c.scope, split.id)])
             |> Map.values()
             |> List.flatten()

    assert part_id == domain.id
    assert text(view, "#receipts-attached") =~ "Domain · −5,00 €"
  end
end
