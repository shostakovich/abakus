defmodule AbakusWeb.Depot.ImportLiveTest do
  use AbakusWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Abakus.Depot.{Portfolios, PPImport}

  setup :register_and_log_in_user

  defp upload(lv, name, content) do
    lv
    |> file_input("#import-form", :pp_file, [%{name: name, content: content}])
    |> render_upload(name)

    lv |> form("#import-form") |> render_submit()
  end

  test "imports an uploaded PP file and shows what changed", %{conn: conn, scope: scope} do
    {:ok, lv, _html} = live(conn, ~p"/depot/import")

    html = upload(lv, "sample.portfolio", File.read!("test/fixtures/depot/pp/sample.portfolio"))

    assert html =~ "Import abgeschlossen."
    assert lv |> element("#summary-transactions") |> render() =~ "21"
    assert length(Portfolios.list_portfolios(scope)) == 2
  end

  test "a first import opens the Depot", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/depot/import")
    refute has_element?(lv, sidebar_link("/depot/holdings"))

    upload(lv, "sample.portfolio", File.read!("test/fixtures/depot/pp/sample.portfolio"))

    assert has_element?(lv, sidebar_link("/depot/holdings"))
    {:ok, _lv, html} = live(conn, ~p"/depot/holdings")
    assert html =~ "Bestand"
  end

  test "an import that leaves no portfolio closes the Depot", %{conn: conn, scope: scope} do
    {:ok, _summary} = PPImport.run(scope, "test/fixtures/depot/pp/sample.portfolio")
    {:ok, lv, _html} = live(conn, ~p"/depot/import")
    assert has_element?(lv, sidebar_link("/depot/holdings"))

    {:ok, {_name, empty}} =
      :zip.create(~c"empty.portfolio", [{~c"data.portfolio", "PPPBV1"}], [:memory])

    assert upload(lv, "empty.portfolio", empty) =~ "Import abgeschlossen."

    assert Portfolios.list_portfolios(scope) == []
    refute has_element?(lv, sidebar_link("/depot/holdings"))
  end

  test "shows the imported portfolios in the Depot's open pages", %{conn: conn, scope: scope} do
    Portfolios.create_portfolio(scope, %{name: "Eigenes", account_name: "Konto"})
    {:ok, overview, _html} = live(conn, ~p"/depot")
    {:ok, lv, _html} = live(conn, ~p"/depot/import")

    upload(lv, "sample.portfolio", File.read!("test/fixtures/depot/pp/sample.portfolio"))

    assert has_element?(overview, ~s(aside nav[aria-label="Hauptnavigation"]), "Depot A")
  end

  test "explains why a file cannot be imported", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/depot/import")

    html = upload(lv, "notes.portfolio", "no zip")

    assert html =~ "keine (unverschlüsselte) Datei aus Portfolio Performance"
    refute has_element?(lv, "#import-summary")
  end

  test "ignores a submit without a finished upload", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/depot/import")

    lv |> form("#import-form") |> render_submit()

    refute has_element?(lv, "#import-summary")
  end

  test "is a section of the settings, also before the first portfolio", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/settings")
    assert has_element?(lv, ~s(#settings-nav a[href="/depot/import"]), "PP-Import")
  end
end
