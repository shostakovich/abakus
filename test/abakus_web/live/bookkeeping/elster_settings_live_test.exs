defmodule AbakusWeb.Bookkeeping.ElsterSettingsLiveTest do
  use AbakusWeb.ConnCase

  import Phoenix.LiveViewTest
  import Abakus.DomainFixtures
  import Abakus.BookkeepingFixtures
  import AbakusWeb.PageText, only: [text: 2]
  import Setzkasten.Test.Confirm

  alias Abakus.Bookkeeping
  alias Abakus.Bookkeeping.Invoices

  setup :register_and_log_in_user

  test "keeps the state of the tax office, the business and the ELSTER certificate", %{
    conn: conn,
    scope: scope
  } do
    {:ok, _ids} = Bookkeeping.put_business_accounts(scope, [account_fixture(kind: :tracking).id])
    sender_fixture(scope)
    {:ok, view, _html} = live(conn, ~p"/settings/buchhaltung/elster")

    assert has_element?(view, "#settings-elster-settings-sidebar[aria-current=page]")
    assert text(view, "#elster-tax-number") =~ "Steuernummer: 30/123/45678"

    assert text(view, "#elster-status") ==
             "Es fehlt: Bundesland, ELSTER-Zertifikat, Art des Betriebs"

    view
    |> form("#elster-settings-form",
      settings: %{
        "tax_state" => "BE",
        "business_activity" => " Softwareentwicklung ",
        "income_kind" => "trade"
      }
    )
    |> render_submit()

    assert_push_event(view, "setzkasten:saved", %{id: "elster-settings-save"})

    view
    |> file_input("#elster-certificate-form", :certificate, [
      %{name: "Robert.pfx", content: "PKCS12 certificate", type: "application/x-pkcs12"}
    ])
    |> render_upload("Robert.pfx")

    assert text(view, "#elster-certificate-stored") =~ "Robert.pfx"
    assert text(view, "#elster-status") == "Bereit"

    settings = Invoices.get_settings(scope)
    assert {settings.tax_state, settings.elster_certificate} == {"BE", "PKCS12 certificate"}
    assert {settings.business_activity, settings.income_kind} == {"Softwareentwicklung", :trade}
    assert settings.tax_number == "30/123/45678"

    confirm_click(view, "#elster-certificate-remove", "Zertifikat entfernen?")
    refute has_element?(view, "#elster-certificate-stored")
    assert Invoices.get_settings(scope).elster_certificate == nil
  end

  test "is only there with the Buchhaltung", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/settings/buchhaltung/accounts")
    refute has_element?(view, ~s|a[href="/settings/buchhaltung/elster"]|)
    assert_error_sent 404, fn -> get(conn, ~p"/settings/buchhaltung/elster") end
  end
end
