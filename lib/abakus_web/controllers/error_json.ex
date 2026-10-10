defmodule AbakusWeb.ErrorJSON do
  @moduledoc false

  alias AbakusWeb.Api

  @api_details %{
    400 => "Ungültige Anfrage",
    404 => "Nicht gefunden",
    406 => "Format nicht unterstützt",
    413 => "Anfrage zu groß",
    415 => "Format nicht unterstützt",
    500 => "Interner Fehler"
  }

  # The API answers in YNAB's error format, also for errors raised before its actions (e.g. a body that is no JSON
  # or a path outside `/api/v1`).
  def render(template, %{conn: %Plug.Conn{path_info: ["api" | _]}}) do
    status = template |> String.split(".") |> hd() |> String.to_integer()
    Api.error_body(status, Map.get(@api_details, status, "Fehler #{status}"))
  end

  def render(template, _assigns),
    do: %{errors: %{detail: Phoenix.Controller.status_message_from_template(template)}}
end
