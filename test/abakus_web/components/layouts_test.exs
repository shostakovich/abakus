defmodule AbakusWeb.LayoutsTest do
  use AbakusWeb.ConnCase

  test "the root layout links the manifest, sets theme colours and the theme before the stylesheet",
       %{
         conn: conn
       } do
    html = conn |> get(~p"/") |> html_response(200)
    document = LazyHTML.from_document(html)

    assert document |> LazyHTML.query("html[lang=de]") |> Enum.count() == 1
    assert document |> LazyHTML.query("html[data-look]") |> Enum.empty?()

    assert document
           |> LazyHTML.query(~s|link[rel=manifest][href="/manifest.webmanifest"]|)
           |> Enum.count() == 1

    theme_colors =
      document
      |> LazyHTML.query("meta[name=theme-color]")
      |> Enum.map(&{LazyHTML.attribute(&1, "media"), LazyHTML.attribute(&1, "content")})

    assert theme_colors == [
             {["(prefers-color-scheme: light)"], ["#3f7d5a"]},
             {["(prefers-color-scheme: dark)"], ["#212529"]}
           ]

    [script] = document |> LazyHTML.query("head script#theme-script") |> Enum.to_list()
    assert LazyHTML.text(script) =~ ~s|localStorage.getItem("theme")|

    # The stored theme has to be applied before felt.css paints the page.
    {script_at, _} = :binary.match(html, ~s(id="theme-script"))
    {css_at, _} = :binary.match(html, "felt-css.rocu.de/felt.css")
    assert script_at < css_at
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
