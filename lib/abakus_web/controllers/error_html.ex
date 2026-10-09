defmodule AbakusWeb.ErrorHTML do
  @moduledoc "Error pages in German, without the app's layout and scripts."
  use AbakusWeb, :html

  @messages %{
    "400" => "Ungültige Anfrage",
    "403" => "Zugriff verweigert",
    "404" => "Seite nicht gefunden",
    "406" => "Format nicht unterstützt",
    "413" => "Anfrage zu groß",
    "415" => "Format nicht unterstützt",
    "500" => "Interner Fehler"
  }

  def render(template, _assigns) do
    [status | _format] = String.split(template, ".")
    assigns = %{message: Map.get(@messages, status, "Fehler #{status}")}

    ~H"""
    <!DOCTYPE html>
    <html lang="de">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <title>{@message} · Abakus</title>
        <link rel="stylesheet" href="https://felt-css.rocu.de/felt.css" />
      </head>
      <body>
        <main class="container py-5">
          <h1>{@message}</h1>
          <p><a href="/">Zur Startseite</a></p>
        </main>
      </body>
    </html>
    """
  end
end
