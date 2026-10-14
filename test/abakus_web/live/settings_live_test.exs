defmodule AbakusWeb.SettingsLiveTest do
  use AbakusWeb.ConnCase

  import Phoenix.LiveViewTest
  import Abakus.DomainFixtures

  alias Abakus.YnabImport

  @fixture Path.expand("../../fixtures/ynab/plan.json", __DIR__)
  @external_resource @fixture
  @plan @fixture |> File.read!() |> JSON.decode!() |> Map.fetch!("plan")

  @sections [
    {"Zugang & API", "/settings/access"},
    {"Aussehen", "/settings/appearance"},
    {"YNAB-Import", "/settings/ynab"}
  ]

  setup :register_and_log_in_user

  describe "section navigation" do
    @tag signed_in_minutes_ago: 11
    test "the overview and the sections beside Zugang & API need no recent sign-in", %{
      conn: conn
    } do
      for path <- [~p"/settings/appearance", ~p"/settings/ynab"],
          do: assert({:ok, _view, _html} = live(conn, path))

      assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/settings/access")

      {:ok, view, _html} = live(conn, ~p"/settings")

      assert has_element?(view, "h1", "Einstellungen")
      assert has_element?(view, "#side-settings-sidebar[aria-current=page]")

      for {label, path} <- @sections do
        assert has_element?(view, ~s|#settings-nav a[href="#{path}"]:not([data-phx-link])|, label)
      end

      refute has_element?(view, "#settings-nav a[aria-current]")
      refute has_element?(view, ~s|main header a[href="/settings"]|)
    end

    test "every section marks itself in the navigation and leads back to the overview", %{
      conn: conn
    } do
      for {label, path} <- @sections do
        {:ok, view, _html} = live(conn, path)

        assert has_element?(view, ~s|#settings-nav a[aria-current=page][href="#{path}"]|, label)
        refute has_element?(view, ~s|#settings-nav a[aria-current]:not([href="#{path}"])|)
        assert has_element?(view, ~s|main header a[href="/settings"]|, "Einstellungen")
        assert has_element?(view, "h1", label)
        assert has_element?(view, "#side-settings-sidebar[aria-current=page]")
      end
    end

    test "Zugang & API holds passkeys, email and tokens; Aussehen the theme", %{conn: conn} do
      {:ok, access, _html} = live(conn, ~p"/settings/access")

      assert has_element?(access, "#passkeys")
      assert has_element?(access, "#email-form")
      assert has_element?(access, "#api-tokens")
      refute has_element?(access, "#theme-toggle")

      {:ok, appearance, _html} = live(conn, ~p"/settings/appearance")

      assert has_element?(appearance, "#appearance", "Gilt für dieses Gerät")
      assert has_element?(appearance, "#appearance #theme-toggle[phx-hook]")

      for label <- ["System", "Hell", "Dunkel"],
          do: assert(has_element?(appearance, "#theme-toggle label", label))
    end
  end

  describe "YNAB import status" do
    test "says when nothing came from YNAB", %{conn: conn} do
      transaction_fixture()

      {:ok, view, _html} = live(conn, ~p"/settings/ynab")

      assert has_element?(view, "#ynab-import", "Noch nichts aus YNAB übernommen.")
      refute has_element?(view, "#ynab-import-summary")
    end

    test "shows when the import ran and what it brought over", %{conn: conn} do
      {:ok, _report} = YnabImport.import_plan(@plan)
      %{imported_at: imported_at} = YnabImport.status()

      {:ok, view, _html} = live(conn, ~p"/settings/ynab")

      assert has_element?(
               view,
               "#ynab-import",
               "übernommen am #{Calendar.strftime(imported_at, "%d.%m.%Y")}"
             )

      assert has_element?(
               view,
               "#ynab-import-summary",
               "4 Konten, 3 Kategoriegruppen mit 7 Kategorien, 5 Empfänger, 18 Buchungen, " <>
                 "Budget ab August 2026."
             )
    end
  end
end
