defmodule AbakusWeb.LayoutsTest do
  use AbakusWeb.ConnCase

  alias Abakus.Depot.Portfolios.Portfolio
  alias Abakus.Ledger.Account
  alias Abakus.Users.{Scope, User}
  alias AbakusWeb.AccountGroups

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

    [script, device] = document |> LazyHTML.query("head script[nonce]") |> Enum.to_list()
    assert LazyHTML.text(script) =~ ~s|localStorage.getItem("setzkasten:theme")|
    assert LazyHTML.text(script) =~ ~s|localStorage.getItem("setzkasten:sidebar")|
    assert LazyHTML.text(device) =~ ~s|localStorage.getItem("abakus:register-memo")|
    assert LazyHTML.text(device) =~ ~s|setAttribute("data-register-memo", "hidden")|
    assert LazyHTML.text(device) =~ ~s|localStorage.getItem("abakus:budget-calculation")|
    assert LazyHTML.text(device) =~ ~s|setAttribute("data-budget-calculation", "shown")|

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

    for path <- [~p"/settings/access", ~p"/settings/appearance", ~p"/settings/budget/ynab"] do
      page = conn |> get(path) |> html_response(200) |> LazyHTML.from_document()

      assert page |> LazyHTML.query(~s|a[href="/settings/access"]|) |> Enum.any?()
      assert page |> LazyHTML.query(~s|a[href="/budget"]:not([data-phx-link])|) |> Enum.any?()
    end
  end

  describe "Finanzen's sidebar" do
    import Phoenix.Component, only: [sigil_H: 2]
    import Phoenix.LiveViewTest, only: [rendered_to_string: 1]

    test "shows the entries' plush, for a portfolio without emoji the briefcase" do
      assigns = %{
        areas: [
          %{key: :finanzen, label: "Finanzen", plush: "wallet", icon: "wallet", path: "/budget"}
        ],
        scope: %Scope{user: %User{email: "kim@example.com", budget_owner: true}, depot: true},
        sidebar: %{
          portfolios: [%{portfolio: %Portfolio{id: 7, name: "Langfristig"}, value: 100}],
          inbox: 0
        }
      }

      html =
        ~H"""
        <AbakusWeb.Layouts.app
          flash={%{}}
          current_scope={@scope}
          areas={@areas}
          area={:finanzen}
          depot_sidebar={@sidebar}
        >
          Inhalt
        </AbakusWeb.Layouts.app>
        """
        |> rendered_to_string()
        |> LazyHTML.from_fragment()

      for {id, plush} <- [
            {"side-budget", "wallet"},
            {"side-depot-wealth", "trending-up"},
            {"side-all-accounts", "landmark"},
            {"side-depots", "briefcase"},
            {"side-import", "inbox"},
            {"side-depot-portfolio-7", "briefcase"},
            {"side-settings", "settings"}
          ] do
        selector = ~s|##{id}-sidebar img[src^="/images/plush/#{plush}"]|
        assert html |> LazyHTML.query(selector) |> Enum.any?(), selector
      end
    end

    test "shows an account's emoji, for one without emoji its kind's plush" do
      accounts = [
        %Account{id: 1, name: "Girokonto", kind: :checking},
        %Account{id: 2, name: "💶 Bargeld", kind: :cash}
      ]

      assigns = %{
        areas: [
          %{key: :finanzen, label: "Finanzen", plush: "wallet", icon: "wallet", path: "/budget"}
        ],
        scope: %Scope{user: %User{email: "kim@example.com", budget_owner: true}},
        groups: AccountGroups.build(accounts, %{})
      }

      html =
        ~H"""
        <AbakusWeb.Layouts.app
          flash={%{}}
          current_scope={@scope}
          areas={@areas}
          area={:finanzen}
          account_groups={@groups}
        >
          Inhalt
        </AbakusWeb.Layouts.app>
        """
        |> rendered_to_string()
        |> LazyHTML.from_fragment()

      assert html
             |> LazyHTML.query(~s|#side-account-1-sidebar img[src^="/images/plush/landmark"]|)
             |> Enum.any?()

      cash = LazyHTML.query(html, "#side-account-2-sidebar")
      assert LazyHTML.text(cash) =~ "💶"
      assert cash |> LazyHTML.query("img") |> Enum.empty?()
    end
  end

  describe "with more than one area" do
    import Phoenix.Component, only: [sigil_H: 2]
    import Phoenix.LiveViewTest, only: [rendered_to_string: 1]

    @areas [
      %{key: :finanzen, label: "Finanzen", plush: "wallet", icon: "wallet", path: "/budget"},
      %{key: :kasse, label: "Kasse", plush: "receipt", icon: "receipt", path: "/kasse"}
    ]

    defp app_with_areas(area) do
      assigns = %{
        areas: @areas,
        area: area,
        scope: %Scope{user: %User{email: "kim@example.com", budget_owner: true}}
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

    defp hrefs(html, selector),
      do: html |> LazyHTML.query(selector) |> Enum.flat_map(&LazyHTML.attribute(&1, "href"))

    test "the sidebar switches the area under the brand Abakus and shows only the current one" do
      html = app_with_areas(:kasse)

      assert html |> texts("#app-shell-sidebar-full") |> hd() =~ "Abakus"

      assert html
             |> LazyHTML.query(~s|#app-shell-sidebar-full nav[aria-label="Bereich wechseln"] a|)
             |> Enum.map(
               &{LazyHTML.attribute(&1, "href"), LazyHTML.attribute(&1, "aria-current")}
             ) ==
               [{["/budget"], []}, {["/kasse"], ["page"]}]

      sidebar = ~s|#app-shell-sidebar-full nav[aria-label="Hauptnavigation"] a|
      assert "/kasse/balances" in hrefs(html, sidebar)
      refute "/budget" in hrefs(html, sidebar)
      assert "/budget" in hrefs(app_with_areas(:finanzen), sidebar)
      refute "/kasse" in hrefs(app_with_areas(:finanzen), sidebar)
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

    test "the area switch and the top bar's area menu show the areas' plush" do
      html = app_with_areas(:kasse)

      for {key, path, plush} <- [{:finanzen, "/budget", "wallet"}, {:kasse, "/kasse", "receipt"}],
          selector <- [
            ~s|#area-#{key}-sidebar img[src^="/images/plush/#{plush}"]|,
            ~s|#area-switcher a[href="#{path}"] img[src^="/images/plush/#{plush}"]|
          ],
          do: assert(html |> LazyHTML.query(selector) |> Enum.any?(), selector)
    end

    test "the dock holds only the current area's pages" do
      assert hrefs(app_with_areas(:kasse), ".dock a") ==
               ["/kasse", "/kasse/balances", "/kasse/activity"]

      assert hrefs(app_with_areas(:finanzen), ".dock a") ==
               ["/budget", "/depot", "/budget/accounts/all"]
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
