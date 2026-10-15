defmodule AbakusWeb.LayoutsTest do
  use AbakusWeb.ConnCase

  alias Abakus.Users.{Scope, User}

  test "the root layout links the manifest, sets theme colours and the theme before the stylesheet",
       %{conn: conn} do
    html = conn |> get(~p"/users/log-in") |> html_response(200)
    document = LazyHTML.from_document(html)

    assert document |> LazyHTML.query("html[lang=de]") |> Enum.count() == 1

    assert document
           |> LazyHTML.query(~s|meta[name=viewport][content*="viewport-fit=cover"]|)
           |> Enum.count() == 1

    assert document
           |> LazyHTML.query(~s|link[rel=manifest][href="/manifest.webmanifest"]|)
           |> Enum.count() == 1

    theme_colors =
      document
      |> LazyHTML.query("meta[name=theme-color]")
      |> Enum.map(&{LazyHTML.attribute(&1, "media"), LazyHTML.attribute(&1, "content")})

    assert theme_colors == [
             {["(prefers-color-scheme: light)"], ["#ffffff"]},
             {["(prefers-color-scheme: dark)"], ["#202328"]}
           ]

    [script] = document |> LazyHTML.query("head script[nonce]") |> Enum.to_list()
    assert LazyHTML.text(script) =~ ~s|localStorage.getItem("setzkasten:theme")|
    assert LazyHTML.text(script) =~ ~s|localStorage.getItem("setzkasten:sidebar")|

    assert document
           |> LazyHTML.query(
             ~s|link[rel=preload][as=font][href="/setzkasten/fonts/Figtree-Variable.woff2"]|
           )
           |> Enum.count() == 1

    # The stored theme has to be applied before the stylesheet paints the page.
    {script_at, _} = :binary.match(html, "setzkasten:theme")
    {css_at, _} = :binary.match(html, "/assets/css/app.css")
    assert script_at < css_at
  end

  test "the endpoint serves Setzkasten's fonts", %{conn: conn} do
    conn = get(conn, "/setzkasten/fonts/Figtree-Variable.woff2")
    assert response(conn, 200)
    assert get_resp_header(conn, "content-type") == ["font/woff2"]
  end

  test "links within the Budget navigate; links into and out of the settings load the page" do
    user = Abakus.UsersFixtures.user_fixture()
    conn = log_in_user(build_conn(), user)

    budget = conn |> get(~p"/budget") |> html_response(200) |> LazyHTML.from_document()
    settings_links = budget |> LazyHTML.query(~s|a[href="/settings"]|) |> Enum.to_list()
    budget_links = budget |> LazyHTML.query(~s|a[href="/budget/accounts/all"]|) |> Enum.to_list()

    assert settings_links != []
    assert Enum.all?(settings_links, &(LazyHTML.attribute(&1, "data-phx-link") == []))
    assert budget_links != []
    assert Enum.all?(budget_links, &(LazyHTML.attribute(&1, "data-phx-link") != []))
    assert budget |> LazyHTML.query(~s|a[href="/settings/access"]|) |> Enum.empty?()

    for path <- [
          ~p"/settings",
          ~p"/settings/access",
          ~p"/settings/appearance",
          ~p"/settings/ynab"
        ] do
      page = conn |> get(path) |> html_response(200) |> LazyHTML.from_document()

      assert page |> LazyHTML.query(~s|a[href="/settings/access"]|) |> Enum.any?()
      assert page |> LazyHTML.query("a[data-phx-link]") |> Enum.empty?()
    end
  end

  describe "with more than one area" do
    import Phoenix.Component, only: [sigil_H: 2]
    import Phoenix.LiveViewTest, only: [rendered_to_string: 1]

    @areas [
      %{key: :budget, label: "Budget", icon: "wallet", path: "/budget"},
      %{key: :kasse, label: "Kasse", icon: "history", path: "/kasse"}
    ]

    defp app_with_areas(area) do
      assigns = %{
        areas: @areas,
        area: area,
        scope: Scope.for_user(%User{email: "kim@example.com"})
      }

      ~H"""
      <AbakusWeb.Layouts.app flash={%{}} current_scope={@scope} areas={@areas} area={@area}>
        Inhalt
      </AbakusWeb.Layouts.app>
      """
      |> rendered_to_string()
      |> LazyHTML.from_fragment()
    end

    defp texts(html, selector), do: html |> LazyHTML.query(selector) |> Enum.map(&LazyHTML.text/1)

    test "the sidebar groups the entries by area under the brand Abakus" do
      html = app_with_areas(:kasse)

      assert texts(html, "#app-shell-sidebar-full .menu-title") |> Enum.map(&String.trim/1) == [
               "Budget",
               "Kasse"
             ]

      assert html |> texts("#app-shell-sidebar-full") |> hd() =~ "Abakus"
    end

    test "the top bar's title switches the area" do
      html = app_with_areas(:kasse)

      assert html |> texts("header #area-switcher summary") |> hd() =~ "Kasse"

      assert html
             |> LazyHTML.query("#area-switcher li a")
             |> Enum.map(
               &{LazyHTML.attribute(&1, "href"), LazyHTML.attribute(&1, "aria-current")}
             ) ==
               [{["/budget"], []}, {["/kasse"], ["page"]}]
    end

    test "the dock holds only the current area's entries" do
      dock = fn area ->
        area
        |> app_with_areas()
        |> LazyHTML.query(".dock a")
        |> Enum.flat_map(&LazyHTML.attribute(&1, "href"))
      end

      assert dock.(:kasse) == ["/kasse"]
      assert "/budget" in dock.(:budget)
      refute "/kasse" in dock.(:budget)
    end
  end

  test "the manifest is served as a static file and lists installable icons", %{conn: conn} do
    manifest = conn |> get("/manifest.webmanifest") |> response(200) |> JSON.decode!()

    assert %{"id" => "/", "start_url" => "/", "scope" => "/", "lang" => "de", "icons" => icons} =
             manifest

    assert Enum.map(icons, &Map.take(&1, ["src", "sizes", "type", "purpose"])) == [
             %{
               "src" => "/images/icon.svg",
               "sizes" => "any",
               "type" => "image/svg+xml",
               "purpose" => "any"
             },
             %{
               "src" => "/images/icon-192.png",
               "sizes" => "192x192",
               "type" => "image/png",
               "purpose" => "any"
             },
             %{
               "src" => "/images/icon-512.png",
               "sizes" => "512x512",
               "type" => "image/png",
               "purpose" => "any"
             }
           ]

    for %{"src" => src, "sizes" => sizes, "type" => "image/png"} <- icons do
      conn = get(build_conn(), src)
      assert get_resp_header(conn, "content-type") == ["image/png"]

      <<137, "PNG", _::binary-size(12), width::32, height::32, _::binary>> = response(conn, 200)
      assert "#{width}x#{height}" == sizes
    end
  end
end
