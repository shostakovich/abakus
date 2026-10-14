defmodule AbakusWeb.ErrorHTMLTest do
  use ExUnit.Case, async: true

  import Phoenix.Template, only: [render_to_string: 4]

  for {status, message} <- [
        {"400", "Ungültige Anfrage"},
        {"403", "Zugriff verweigert"},
        {"404", "Seite nicht gefunden"},
        {"406", "Format nicht unterstützt"},
        {"500", "Interner Fehler"},
        {"503", "Fehler 503"}
      ] do
    test "renders #{status}.html in German" do
      html = render_to_string(AbakusWeb.ErrorHTML, unquote(status), "html", csp_nonce: "n0nce")

      assert html =~ ~s(lang="de")
      assert html =~ "<title>#{unquote(message)} · Abakus</title>"
      assert html =~ ~r{<h1[^>]*>#{unquote(message)}</h1>}
      assert html =~ ~r{<a href="/"[^>]*>Zur Startseite</a>}
      assert html =~ ~s(<link rel="stylesheet" href="/assets/css/app.css")
      refute html =~ "style="
      assert [_theme] = Regex.scan(~r/<script/, html)
      assert html =~ ~r/<script[^>]* nonce="n0nce"/
    end
  end
end
