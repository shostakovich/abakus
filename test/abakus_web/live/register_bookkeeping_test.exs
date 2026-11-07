defmodule AbakusWeb.RegisterBookkeepingTest do
  use AbakusWeb.ConnCase

  import Phoenix.LiveViewTest
  import Abakus.DomainFixtures
  import AbakusWeb.PageText, only: [text: 2]

  alias Abakus.{Bookkeeping, Ledger}

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
end
