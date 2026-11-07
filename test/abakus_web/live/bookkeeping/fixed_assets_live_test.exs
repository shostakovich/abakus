defmodule AbakusWeb.Bookkeeping.FixedAssetsLiveTest do
  use AbakusWeb.ConnCase

  import Phoenix.LiveViewTest
  import Setzkasten.Test.Confirm
  import Abakus.BookkeepingFixtures
  import Abakus.DomainFixtures
  import AbakusWeb.PageText, only: [text: 2, flash: 2]

  alias Abakus.Bookkeeping
  alias Abakus.Bookkeeping.{FakeElster, Filings, FixedAssets}

  setup :register_and_log_in_user

  setup %{scope: scope} do
    kontist = account_fixture(name: "Kontist", kind: :tracking)
    {:ok, _ids} = Bookkeeping.put_business_accounts(scope, [kontist.id])
    fix_today(~D[2027-12-31])
    %{kontist: kontist}
  end

  test "adds an asset with its book value", %{conn: conn, scope: scope} do
    {:ok, view, _html} = live(conn, ~p"/buchhaltung/assets")
    assert has_element?(view, "#side-bookkeeping-assets-sidebar[aria-current=page]")
    assert has_element?(view, "#assets-empty")

    view |> element("#asset-new") |> render_click()

    params = %{
      "name" => "Notebook",
      "purchased_on" => "2027-04-10",
      "net" => "2.400,00",
      "useful_life" => ""
    }

    assert view |> form("#asset-form", fixed_asset: params) |> render_submit() =~
             "Muss ausgefüllt werden"

    view
    |> form("#asset-form", fixed_asset: %{params | "useful_life" => "3"})
    |> render_submit()

    assert [asset] = FixedAssets.list(scope)
    refute has_element?(view, "#asset-form")
    row = "#asset-#{asset.id}"
    assert text(view, row) =~ "gekauft 10.04.2027 · 2.400,00 € netto · 3 Jahre"
    assert text(view, row) =~ "1.800,00 €"
  end

  test "records a sale with its payment, takes it back and deletes the asset", c do
    asset =
      fixed_asset_fixture(c.scope, %{
        "name" => "Lastenrad",
        "purchased_on" => "2025-03-01",
        "net" => "900",
        "useful_life" => "3"
      })

    payee = payee_fixture(name: "Autohaus Nord")

    payment =
      transaction_fixture(
        account_id: c.kontist.id,
        date: ~D[2027-01-22],
        amount: 23_800,
        payee_id: payee.id
      )

    {:ok, view, _html} = live(c.conn, ~p"/buchhaltung/assets")
    row = "#asset-#{asset.id}"
    view |> element("#{row}-dispose-menu-item") |> render_click()

    view
    |> form("#disposal-form",
      disposal: %{"kind" => "sale", "date" => "2027-01-20", "amount" => "238", "vat" => "19"}
    )
    |> render_change()

    assert text(view, "#disposal-book-value") == "Restbuchwert am 20.01.2027 325,00 €"

    assert text(view, "#disposal_transaction_id option[value='#{payment.id}']") ==
             "22.01.2027 · Autohaus Nord · 238,00 €"

    view
    |> form("#disposal-form", disposal: %{"transaction_id" => payment.id})
    |> render_submit()

    assert FixedAssets.get(c.scope, asset.id).disposal.transaction_id == payment.id
    assert text(view, row) =~ "verkauft am 20.01.2027 für 238,00 €"
    assert text(view, row) =~ "0,00 €"

    confirm_click(view, "#{row}-undispose-menu-item", "Abgang zurücknehmen?")
    assert FixedAssets.get(c.scope, asset.id).disposal == nil
    assert text(view, row) =~ "50,00 €"

    confirm_click(view, "#{row}-delete-menu-item", "„Lastenrad“ löschen?")
    assert FixedAssets.list(c.scope) == []
    assert has_element?(view, "#assets-empty")
  end

  test "keeps a disposal of a sent quarter in the register", c do
    asset = fixed_asset_fixture(c.scope, %{"name" => "Lastenrad", "purchased_on" => "2025-03-01"})
    disposal_fixture(c.scope, asset, %{"date" => "2027-01-20"})
    elster_fixture(c.scope)
    FakeElster.serve()
    {:ok, _filing} = Filings.send_return(c.scope, {:vat_quarter, 2027, 1}, "4711")

    {:ok, view, _html} = live(c.conn, ~p"/buchhaltung/assets")
    row = "#asset-#{asset.id}"

    confirm_click(view, "#{row}-undispose-menu-item", "Abgang zurücknehmen?")
    assert flash(view, :error) =~ "Zeitraum ist festgeschrieben"

    confirm_click(view, "#{row}-delete-menu-item", "„Lastenrad“ löschen?")
    assert flash(view, :error) =~ "Zeitraum ist festgeschrieben"
    assert FixedAssets.get(c.scope, asset.id).disposal.date == ~D[2027-01-20]
  end
end
