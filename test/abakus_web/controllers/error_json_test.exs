defmodule AbakusWeb.ErrorJSONTest do
  use ExUnit.Case, async: true

  test "renders 404" do
    assert AbakusWeb.ErrorJSON.render("404.json", %{}) == %{errors: %{detail: "Not Found"}}
  end

  test "renders 500" do
    assert AbakusWeb.ErrorJSON.render("500.json", %{}) ==
             %{errors: %{detail: "Internal Server Error"}}
  end

  test "renders YNAB's error format under /api" do
    conn = %Plug.Conn{path_info: ["api", "v1", "plans"]}

    assert AbakusWeb.ErrorJSON.render("400.json", %{conn: conn}) ==
             %{error: %{id: "400", name: "bad_request", detail: "Ungültige Anfrage"}}

    assert AbakusWeb.ErrorJSON.render("404.json", %{conn: conn}) ==
             %{error: %{id: "404.2", name: "resource_not_found", detail: "Nicht gefunden"}}

    assert AbakusWeb.ErrorJSON.render("500.json", %{conn: conn}) ==
             %{error: %{id: "500", name: "internal_server_error", detail: "Interner Fehler"}}

    assert AbakusWeb.ErrorJSON.render("413.json", %{conn: conn}).error.detail ==
             "Anfrage zu groß"
  end
end
