defmodule AbakusWeb.Depot.ReceiptIntakeLiveTest do
  use AbakusWeb.ConnCase

  import Phoenix.LiveViewTest
  import Abakus.Depot.PortfoliosFixtures

  alias Abakus.Depot.{FakeModel, Settings}

  setup :register_and_log_in_user

  setup %{scope: scope} do
    portfolio_fixture(scope)
    :ok
  end

  defp status(lv, id) do
    lv
    |> element("#{id} [data-detail]")
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.query("[data-part]")
    |> Enum.map(&LazyHTML.text/1)
  end

  defp save_paperless(lv, params),
    do: lv |> form("#paperless-form", %{"paperless" => params}) |> render_submit()

  test "is a section of the settings once the user has the Depot", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/settings")
    assert has_element?(lv, ~s(#settings-nav a[href="/depot/receipt-intake"]), "Belegeingang")
  end

  test "is not there without the Depot" do
    %{conn: conn} = register_and_log_in_user(%{conn: build_conn()})

    {:ok, lv, _html} = live(conn, ~p"/settings")
    refute has_element?(lv, ~s(#settings-nav a[href="/depot/receipt-intake"]))
    assert_error_sent 404, fn -> get(conn, ~p"/depot/receipt-intake") end
  end

  test "connects the user's Paperless and never shows the token again", %{conn: conn} = ctx do
    {:ok, lv, _html} = live(conn, ~p"/depot/receipt-intake")
    assert has_element?(lv, "#paperless-status [data-status]", "Nicht verbunden")
    refute has_element?(lv, "#paperless-form button", "Trennen")

    result =
      save_paperless(lv, %{
        "paperless_url" => " https://paperless.example.org/ ",
        "paperless_token" => "geheim123",
        "paperless_tag" => "abakus"
      })

    assert_push_event(lv, "setzkasten:saved", %{id: "paperless-save"})
    assert has_element?(lv, "#paperless-save.setzkasten-saved")
    refute has_element?(lv, "#flash-info")
    refute result =~ "geheim123"

    assert has_element?(lv, "#paperless-status [data-status]", "Verbunden")

    assert status(lv, "#paperless-status") ==
             ["Tag „abakus“,", "danach „abakus-erledigt“ ·", "noch nicht abgefragt"]

    settings = Settings.get_settings(ctx.scope)
    assert settings.paperless_url == "https://paperless.example.org"
    assert settings.paperless_token == "geheim123"
    refute inspect(settings) =~ "geheim123"

    save_paperless(lv, %{"paperless_token" => "", "paperless_tag" => "belege"})
    assert Settings.get_settings(ctx.scope).paperless_token == "geheim123"
    assert has_element?(lv, "#paperless-status", "Tag „belege“")

    confirm_click(lv, "#paperless-disconnect", "Paperless trennen?")
    assert has_element?(lv, "#paperless-status", "Nicht verbunden")
    assert Settings.get_settings(ctx.scope).paperless_token == nil
  end

  test "shows when Paperless was polled last", %{conn: conn, scope: scope} do
    {:ok, settings} =
      Settings.update_paperless(scope, %{
        "paperless_url" => "http://paperless:8000",
        "paperless_token" => "t",
        "paperless_tag" => "abakus"
      })

    :ok = Settings.paperless_polled(settings)
    {:ok, lv, _html} = live(conn, ~p"/depot/receipt-intake")

    assert has_element?(lv, "#paperless-status", "zuletzt abgefragt")
  end

  test "refuses a URL without scheme and a missing token or tag", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/depot/receipt-intake")

    result = save_paperless(lv, %{"paperless_url" => "paperless.local"})

    assert result =~ "Braucht http:// oder https:// und einen Host"
    refute_push_event(lv, "setzkasten:saved", %{id: "paperless-save"})
    assert has_element?(lv, ~s(#paperless-form p[id$="-error-0"]), "Muss ausgefüllt werden")
    assert has_element?(lv, "#paperless-status", "Nicht verbunden")
  end

  test "names the recognition model, or that there is none", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/depot/receipt-intake")
    assert has_element?(lv, "#recognition-status [data-status]", "Kein Modell")

    FakeModel.stub(fn _text -> {:ok, "{}"} end)
    {:ok, lv, _html} = live(conn, ~p"/depot/receipt-intake")
    assert has_element?(lv, "#recognition-status [data-status]", "Eingerichtet")
    assert ["Testmodell ·", "Text aus Paperless," | _rest] = status(lv, "#recognition-status")
  end
end
