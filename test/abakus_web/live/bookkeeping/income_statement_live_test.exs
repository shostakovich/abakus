defmodule AbakusWeb.Bookkeeping.IncomeStatementLiveTest do
  use AbakusWeb.ConnCase

  import Phoenix.LiveViewTest
  import Abakus.BookkeepingFixtures
  import Abakus.DomainFixtures
  import AbakusWeb.PageText, only: [text: 2]

  alias Abakus.Bookkeeping

  setup :register_and_log_in_user

  setup %{scope: scope} do
    kontist = account_fixture(name: "Kontist", kind: :tracking)
    {:ok, _ids} = Bookkeeping.put_business_accounts(scope, [kontist.id])
    fix_today(~D[2028-03-15])

    transaction =
      transaction_fixture(account_id: kontist.id, date: ~D[2027-01-20], amount: 119_000)

    {:ok, _lines} =
      Bookkeeping.save_tax_lines(scope, Bookkeeping.get_transaction(scope, transaction.id), %{
        "transaction" => %{"category" => "revenue", "vat" => "19"}
      })

    fixed_asset_fixture(scope, %{"purchased_on" => "2027-04-10", "net" => "2.400"})
    :ok
  end

  defp cell(view, row, column), do: text(view, "#euer-#{row} > :nth-child(#{column})")

  test "shows the year to file next under the Kennzahlen of the Anlage EÜR", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/buchhaltung/euer")

    assert has_element?(view, "#side-bookkeeping-euer-sidebar[aria-current=page]")
    assert html =~ "Einnahmenüberschussrechnung 2027"
    assert cell(view, "112", 2) == "112"
    assert cell(view, "112", 3) == "1.000,00 €"
    assert cell(view, "140", 3) == "190,00 €"
    assert cell(view, "130", 3) == "600,00 €"
    assert cell(view, "income", 3) == "1.190,00 €"
    assert cell(view, "expenses", 3) == "600,00 €"
    assert cell(view, "profit", 3) == "590,00 €"
  end

  test "switches to the years before and after", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/buchhaltung/euer")

    view |> element("#euer-later") |> render_click()
    assert_patch(view, ~p"/buchhaltung/euer?year=2028")
    assert cell(view, "130", 3) == "800,00 €"
    refute has_element?(view, "#euer-112")

    view |> element("#euer-earlier") |> render_click()
    assert_patch(view, ~p"/buchhaltung/euer?year=2027")
    assert cell(view, "112", 3) == "1.000,00 €"
  end
end
