defmodule AbakusWeb.ErrorHTML do
  @moduledoc "Error pages in German, without the app's layout and scripts but with the stored theme."
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

  def render(template, assigns) do
    [status | _format] = String.split(template, ".")

    assigns = %{
      message: Map.get(@messages, status, "Fehler #{status}"),
      csp_nonce: assigns[:csp_nonce]
    }

    ~H"""
    <!DOCTYPE html>
    <html lang="de">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover" />
        <.theme_meta />
        <.theme_script nonce={@csp_nonce} />
        <title>{@message} · Abakus</title>
        <link rel="stylesheet" href={~p"/assets/css/app.css"} />
      </head>
      <body class="bg-base-100 text-base-content">
        <main class="mx-auto max-w-md px-4 py-12">
          <h1 class="text-2xl font-semibold">{@message}</h1>
          <p class="mt-4"><a href="/" class="link link-primary">Zur Startseite</a></p>
        </main>
      </body>
    </html>
    """
  end
end
