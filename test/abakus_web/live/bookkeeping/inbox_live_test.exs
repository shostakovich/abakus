defmodule AbakusWeb.Bookkeeping.InboxLiveTest do
  use AbakusWeb.ConnCase

  import Phoenix.LiveViewTest
  import Abakus.DomainFixtures
  import AbakusWeb.PageText, only: [text: 2]

  alias Abakus.Bookkeeping

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

  test "works through the business transactions missing a category, one after another", c do
    {:ok, view, _html} = live(c.conn, ~p"/buchhaltung")

    assert has_element?(view, "#side-bookkeeping-inbox-sidebar[aria-current=page]", "Posteingang")
    assert has_element?(view, "header", "2 geschäftliche Buchungen ohne Kategorie.")
    assert has_element?(view, "#inbox-#{c.hosting.id}", "Kontist")

    view |> element("#inbox-#{c.hosting.id} button", "Hosting GmbH") |> render_click()
    assert has_element?(view, "#tax-lines-transaction", "Hosting GmbH")
    assert has_element?(view, "#tax-lines-save", "Speichern und weiter")

    choose(view, "internet")
    assert has_element?(view, "#tax-transaction-vat option[value='19'][selected]")
    assert text(view, "#tax-transaction-amounts") == "Netto −19,90 € · USt −3,78 €"

    save(view)
    refute has_element?(view, "#inbox-#{c.hosting.id}")
    assert has_element?(view, "#tax-lines-transaction", "Software Ltd")
    assert has_element?(view, "#tax-lines-save", "Speichern")
    refute has_element?(view, "#tax-lines-save", "weiter")

    choose(view, "licenses_13b_eu")
    assert has_element?(view, "#tax-transaction-vat option[value='reverse_charge'][selected]")
    assert text(view, "#tax-transaction-amounts") == "Netto −100,00 € · USt −19,00 €"

    save(view)
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
end
