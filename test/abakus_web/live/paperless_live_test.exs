defmodule AbakusWeb.PaperlessLiveTest do
  use AbakusWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Abakus.Depot.Receipts.PaperlessJob
  alias Abakus.Depot.Settings
  alias Abakus.Paperless

  setup :register_and_log_in_user

  defp save(lv, params),
    do: lv |> form("#paperless-form", %{"paperless" => params}) |> render_submit()

  test "is a section of Allgemein for every user", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/settings/paperless")

    assert has_element?(lv, "h1", "Paperless")
    assert has_element?(lv, "#settings-paperless-sidebar[aria-current=page]", "Paperless")
  end

  test "connects the user's Paperless and never shows the token again", %{conn: conn} = ctx do
    {:ok, lv, _html} = live(conn, ~p"/settings/paperless")
    assert has_element?(lv, "#paperless-status", "Nicht verbunden")
    refute has_element?(lv, "#paperless-form button", "Trennen")

    result =
      save(lv, %{"url" => " https://paperless.example.org/ ", "token" => "geheim123"})

    assert_push_event(lv, "setzkasten:saved", %{id: "paperless-save"})
    refute has_element?(lv, "#flash-info")
    refute result =~ "geheim123"
    assert has_element?(lv, "#paperless-status", "Verbunden")

    connection = Paperless.get_connection(ctx.scope)
    assert connection.url == "https://paperless.example.org"
    assert connection.token == "geheim123"

    save(lv, %{"url" => "https://paperless.example.org", "token" => ""})
    assert Paperless.get_connection(ctx.scope).token == "geheim123"

    confirm_click(lv, "#paperless-disconnect", "Paperless trennen?")
    assert has_element?(lv, "#paperless-status", "Nicht verbunden")
    refute Paperless.connected?(Paperless.get_connection(ctx.scope))
  end

  test "polls the Depot's receipt intake soon once connected", %{conn: conn, scope: scope} do
    Process.register(self(), PaperlessJob)
    {:ok, _settings} = Settings.update_paperless_tag(scope, %{"paperless_tag" => "abakus"})
    {:ok, lv, _html} = live(conn, ~p"/settings/paperless")

    save(lv, %{"url" => "https://paperless.example.org", "token" => "geheim123"})

    assert_receive {:"$gen_cast", {:poll, %{paperless_tag: "abakus"}}}
  end

  test "refuses a URL without scheme and a missing token", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/settings/paperless")

    result = save(lv, %{"url" => "paperless.local"})

    assert result =~ "Braucht http:// oder https:// und einen Host"
    refute_push_event(lv, "setzkasten:saved", %{id: "paperless-save"})
    assert has_element?(lv, ~s(#paperless-form p[id$="-error-0"]), "Muss ausgefüllt werden")
    assert has_element?(lv, "#paperless-status", "Nicht verbunden")
  end
end
