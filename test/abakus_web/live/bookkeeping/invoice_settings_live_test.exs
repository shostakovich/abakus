defmodule AbakusWeb.Bookkeeping.InvoiceSettingsLiveTest do
  use AbakusWeb.ConnCase

  import Phoenix.LiveViewTest
  import Abakus.DomainFixtures

  alias Abakus.Bookkeeping
  alias Abakus.Bookkeeping.Settings

  setup :register_and_log_in_user

  test "keeps the sender of the invoices", %{conn: conn, scope: scope} do
    {:ok, _ids} = Bookkeeping.put_business_accounts(scope, [account_fixture(kind: :tracking).id])
    {:ok, view, _html} = live(conn, ~p"/settings/buchhaltung/invoices")
    assert has_element?(view, "#settings-invoice-settings-sidebar[aria-current=page]")

    assert view
           |> form("#invoice-settings-form", settings: %{"iban" => "DE00 1234"})
           |> render_change() =~ "Ist keine gültige IBAN"

    view
    |> form("#invoice-settings-form",
      settings: %{
        "name" => "Robert Beispiel",
        "street" => "Lindenallee 4",
        "postal_code" => "10115",
        "city" => "Berlin",
        "tax_number" => "30/123/45678",
        "iban" => "de89 3704 0044 0532 0130 00",
        "payment_days" => "30"
      }
    )
    |> render_submit()

    assert_push_event(view, "setzkasten:saved", %{id: "invoice-settings-save"})
    settings = Settings.get_settings(scope)
    assert {settings.iban, settings.payment_days} == {"DE89370400440532013000", 30}
  end

  test "are only there with the Buchhaltung", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/settings/buchhaltung/accounts")
    refute has_element?(view, ~s|a[href="/settings/buchhaltung/invoices"]|)
    assert_error_sent 404, fn -> get(conn, ~p"/settings/buchhaltung/invoices") end
  end
end
