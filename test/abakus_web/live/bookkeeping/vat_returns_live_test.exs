defmodule AbakusWeb.Bookkeeping.VatReturnsLiveTest do
  use AbakusWeb.ConnCase

  import Phoenix.LiveViewTest
  import Abakus.DomainFixtures
  import AbakusWeb.PageText, only: [text: 2]

  alias Abakus.Bookkeeping

  setup :register_and_log_in_user

  setup %{scope: scope} do
    kontist = account_fixture(name: "Kontist", kind: :tracking)
    {:ok, _ids} = Bookkeeping.put_business_accounts(scope, [kontist.id])
    fix_today(~D[2027-04-15])

    book = fn date, amount, category, vat ->
      transaction = transaction_fixture(account_id: kontist.id, date: date, amount: amount)

      {:ok, _lines} =
        Bookkeeping.save_tax_lines(scope, Bookkeeping.get_transaction(scope, transaction.id), %{
          "transaction" => %{"category" => category, "vat" => vat}
        })
    end

    book.(~D[2027-01-20], 119_000, "revenue", "19")
    book.(~D[2027-02-10], -10_000, "licenses_13b_eu", "reverse_charge")
    book.(~D[2027-05-03], -5_950, "internet", "19")
    :ok
  end

  defp cell(view, row, column), do: text(view, "#vat-#{row} > :nth-child(#{column})")

  test "shows the quarter to file next with its Kennzahlen", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/buchhaltung/vat")

    assert has_element?(view, "#side-bookkeeping-vat-sidebar[aria-current=page]")
    assert html =~ "Voranmeldung 1. Quartal 2027"
    assert cell(view, "sales_19", 3) == "1.000 €"
    assert cell(view, "reverse_charge_eu", 2) == "46"
    assert cell(view, "reverse_charge_eu", 3) == "100 €"
    assert cell(view, "reverse_charge_eu", 5) == "19,00 €"
    assert cell(view, "input_reverse_charge", 5) == "19,00 €"
    assert cell(view, "due", 4) == "83"
    assert cell(view, "due", 5) == "190,00 €"
  end

  test "switches to another quarter and to the year", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/buchhaltung/vat")

    view |> element("#vat-period a", "Q2") |> render_click()
    assert_patch(view, ~p"/buchhaltung/vat?period=2027-q2")
    assert cell(view, "input", 5) == "9,50 €"
    assert cell(view, "due", 5) == "−9,50 €"

    view |> element("#vat-period a", "Jahr") |> render_click()
    assert_patch(view, ~p"/buchhaltung/vat?period=2027")
    assert render(view) =~ "Umsatzsteuererklärung 2027"
    assert cell(view, "sales_19", 2) == "177"
    assert cell(view, "due", 5) == "180,50 €"
    assert cell(view, "prepaid", 5) == "180,50 €"
    assert cell(view, "balance", 4) == "820"
    assert cell(view, "balance", 5) == "0,00 €"

    view |> element("#vat-earlier") |> render_click()
    assert_patch(view, ~p"/buchhaltung/vat?period=2026")
    assert cell(view, "due", 5) == "0,00 €"
  end

  test "falls back to the quarter to file next for a period it cannot read", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/buchhaltung/vat?period=2027-q5")
    assert html =~ "Voranmeldung 1. Quartal 2027"
  end
end
