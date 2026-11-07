defmodule AbakusWeb.Depot.ReceiptIntakeLiveTest do
  use AbakusWeb.ConnCase

  import Phoenix.LiveViewTest
  import Abakus.Depot.PortfoliosFixtures

  alias Abakus.Depot.{FakeModel, Settings}
  alias Abakus.Paperless

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

  defp save_tag(lv, tag),
    do:
      lv
      |> form("#paperless-tag-form", %{"paperless" => %{"paperless_tag" => tag}})
      |> render_submit()

  defp connect(scope),
    do:
      {:ok, _connection} =
        Paperless.update_connection(scope, %{"url" => "http://paperless:8000", "token" => "t"})

  test "is a section of the settings once the user has the Depot", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/settings/depot/receipt-intake")

    assert has_element?(
             lv,
             "#settings-receipt-intake-sidebar[aria-current=page]",
             "Belegeingang"
           )
  end

  test "is not there without the Depot" do
    %{conn: conn} = register_and_log_in_user(%{conn: build_conn()})

    {:ok, lv, _html} = live(conn, ~p"/settings/appearance")
    refute has_element?(lv, "#settings-receipt-intake-sidebar")
    assert_error_sent 404, fn -> get(conn, ~p"/settings/depot/receipt-intake") end
  end

  test "takes documents with the user's tag once Paperless is connected", %{conn: conn} = ctx do
    {:ok, lv, _html} = live(conn, ~p"/settings/depot/receipt-intake")
    assert has_element?(lv, "#paperless-status [data-status]", "Nicht verbunden")
    assert has_element?(lv, ~s|#paperless-link[href="/settings/paperless"]|)

    connect(ctx.scope)
    {:ok, lv, _html} = live(conn, ~p"/settings/depot/receipt-intake")
    assert has_element?(lv, "#paperless-status [data-status]", "Kein Tag")

    save_tag(lv, " abakus ")

    assert_push_event(lv, "setzkasten:saved", %{id: "paperless-tag-save"})
    assert has_element?(lv, "#paperless-status [data-status]", "Verbunden")

    assert status(lv, "#paperless-status") ==
             ["Tag „abakus“,", "danach „abakus-erledigt“ ·", "noch nicht abgefragt"]

    assert Settings.get_settings(ctx.scope).paperless_tag == "abakus"

    save_tag(lv, "")
    assert has_element?(lv, "#paperless-status [data-status]", "Kein Tag")
    assert Settings.get_settings(ctx.scope).paperless_tag == nil
  end

  test "shows when Paperless was polled last", %{conn: conn, scope: scope} do
    connect(scope)
    {:ok, settings} = Settings.update_paperless_tag(scope, %{"paperless_tag" => "abakus"})
    :ok = Settings.paperless_polled(settings)

    {:ok, lv, _html} = live(conn, ~p"/settings/depot/receipt-intake")

    assert has_element?(lv, "#paperless-status", "zuletzt abgefragt")
  end

  test "refuses a tag that is too long", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/settings/depot/receipt-intake")

    save_tag(lv, String.duplicate("a", 101))

    refute_push_event(lv, "setzkasten:saved", %{id: "paperless-tag-save"})
    assert has_element?(lv, ~s(#paperless-tag-form p[id$="-error-0"]))
  end

  test "names the recognition model, or that there is none", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/settings/depot/receipt-intake")
    assert has_element?(lv, "#recognition-status [data-status]", "Kein Modell")

    FakeModel.stub(fn _text -> {:ok, "{}"} end)
    {:ok, lv, _html} = live(conn, ~p"/settings/depot/receipt-intake")
    assert has_element?(lv, "#recognition-status [data-status]", "Eingerichtet")
    assert ["Testmodell ·", "Text aus Paperless," | _rest] = status(lv, "#recognition-status")
  end
end
