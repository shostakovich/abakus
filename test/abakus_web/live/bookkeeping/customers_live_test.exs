defmodule AbakusWeb.Bookkeeping.CustomersLiveTest do
  use AbakusWeb.ConnCase

  import Phoenix.LiveViewTest
  import Abakus.BookkeepingFixtures
  import Abakus.DomainFixtures
  import AbakusWeb.PageText, only: [text: 2]

  alias Abakus.Bookkeeping
  alias Abakus.Bookkeeping.Invoices

  setup :register_and_log_in_user

  setup %{scope: scope} do
    {:ok, _ids} = Bookkeeping.put_business_accounts(scope, [account_fixture(kind: :tracking).id])
    :ok
  end

  test "adds a customer", %{conn: conn, scope: scope} do
    {:ok, view, _html} = live(conn, ~p"/buchhaltung/customers")
    assert has_element?(view, "#customers-empty")

    view |> element("#customer-new") |> render_click()

    assert view
           |> form("#customer-form", customer: %{"name" => "", "street" => ""})
           |> render_submit() =~ "Muss ausgefüllt werden"

    view
    |> form("#customer-form",
      customer: %{
        "name" => "Wiener Werkstatt",
        "street" => "Ring 1",
        "postal_code" => "1010",
        "city" => "Wien",
        "country" => "AT",
        "vat_id" => "atu 12345678"
      }
    )
    |> render_submit()

    assert [customer] = Invoices.list_customers(scope)
    assert customer.vat_id == "ATU12345678"
    refute has_element?(view, "#customer-form")
    assert text(view, "#customer-#{customer.id}") =~ "Ring 1 · 1010 Wien · Österreich"
  end

  test "changes a customer", %{conn: conn, scope: scope} do
    customer = customer_fixture(scope)
    {:ok, view, _html} = live(conn, ~p"/buchhaltung/customers")

    view |> element("#customer-#{customer.id} button", customer.name) |> render_click()
    view |> form("#customer-form", customer: %{"name" => "Muster AG"}) |> render_submit()

    assert has_element?(view, "#customer-#{customer.id}", "Muster AG")
    assert Invoices.get_customer(scope, customer.id).name == "Muster AG"
  end
end
