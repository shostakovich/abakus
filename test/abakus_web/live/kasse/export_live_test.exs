defmodule AbakusWeb.Kasse.ExportLiveTest do
  use AbakusWeb.ConnCase

  import Abakus.KasseFixtures

  import Phoenix.LiveViewTest
  import AbakusWeb.PageText

  setup %{conn: conn} do
    anna = person!("Anna")
    %{conn: log_in_participant(conn, anna.id)}
  end

  defp hrefs(view) do
    for link <- view |> render() |> LazyHTML.from_fragment() |> LazyHTML.query("main a[download]"),
        do: link |> LazyHTML.attribute("href") |> hd()
  end

  defp period(view, from, to),
    do: view |> form("#export-period", %{from: from, to: to}) |> render_change()

  test "downloads everything without a period", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/kasse/export")

    assert page_title(view) == "Export · Abakus"

    assert hrefs(view) == [
             "/kasse/export/expenses.csv",
             "/kasse/export/expenses.json"
           ]

    assert texts(view, "#export-expenses-csv") == ["CSV (Excel, Numbers)"]
    assert has_element?(view, "#export-expenses-csv.btn-primary")
  end

  test "the links follow the period", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/kasse/export")

    period(view, "2026-09-01", "2026-09-30")

    assert hrefs(view) == [
             "/kasse/export/expenses.csv?from=2026-09-01&to=2026-09-30",
             "/kasse/export/expenses.json?from=2026-09-01&to=2026-09-30"
           ]

    period(view, "", "2026-09-30")
    assert hrefs(view) |> hd() == "/kasse/export/expenses.csv?to=2026-09-30"
  end

  test "an end before the start is shown and blocks the downloads", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/kasse/export")

    period(view, "2026-09-30", "2026-09-01")

    assert texts(view, "#to-error-0") == ["„Bis“ liegt vor „Von“."]
    assert hrefs(view) == []
    assert has_element?(view, ~s(a#export-expenses-json[aria-disabled="true"]))
    refute has_element?(view, "a#export-expenses-json[href]")
  end

  test "the period's error shows on the field not typed in too", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/kasse/export?to=2026-09-01")

    render_change(view, "period", %{
      "from" => "2026-09-30",
      "to" => "2026-09-01",
      "_unused_to" => ""
    })

    assert texts(view, "#to-error-0") == ["„Bis“ liegt vor „Von“."]
  end

  test "a period in the address is preset, with its error", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/kasse/export?from=2026-09-30&to=2026-09-01")

    assert has_element?(view, "#from[value='2026-09-30']")
    assert texts(view, "#to-error-0") == ["„Bis“ liegt vor „Von“."]
    assert hrefs(view) == []

    {:ok, view, _html} = live(conn, ~p"/kasse/export?from=broken")
    assert texts(view, "#from-error-0") == ["Ungültiges Datum „broken“."]
    refute has_element?(view, "#to-error-0")

    {:ok, view, _html} = live(conn, ~p"/kasse/export?from=2026-09-01")
    assert hrefs(view) |> hd() == "/kasse/export/expenses.csv?from=2026-09-01"
  end
end
