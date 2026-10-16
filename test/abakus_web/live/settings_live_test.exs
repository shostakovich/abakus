defmodule AbakusWeb.SettingsLiveTest do
  use AbakusWeb.ConnCase

  import Phoenix.LiveViewTest
  import Abakus.Depot.PortfoliosFixtures, only: [portfolio_fixture: 2]
  import Abakus.DomainFixtures
  import Abakus.KasseFixtures

  alias Abakus.Kasse.Participants
  alias Abakus.LocalTime
  alias Abakus.Users.Scope
  alias Abakus.YnabImport

  @fixture Path.expand("../../fixtures/ynab/plan.json", __DIR__)
  @external_resource @fixture
  @plan @fixture |> File.read!() |> JSON.decode!() |> Map.fetch!("plan")

  setup :register_and_log_in_user

  defp hub(view) do
    view
    |> render()
    |> LazyHTML.from_document()
    |> LazyHTML.query(~s|#app-shell-sidebar-full nav[aria-label="Hauptnavigation"] li|)
    |> Enum.map(&(&1 |> LazyHTML.text() |> String.replace(~r/\s+/, " ") |> String.trim()))
    |> Enum.reject(&(&1 == ""))
  end

  defp olga!(user),
    do:
      {:ok, _olga} =
        Participants.create_participant(Scope.system(), %{name: "Olga", email: user.email})

  describe "the hub" do
    @tag signed_in_minutes_ago: 11
    test "opens at Aussehen; only Zugang needs a recent sign-in", %{conn: conn} do
      assert conn |> get(~p"/settings") |> redirected_to() == ~p"/settings/appearance"

      for path <- [~p"/settings/appearance", ~p"/settings/budget/ynab"],
          do: assert({:ok, _view, _html} = live(conn, path))

      assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/settings/access")
    end

    test "lists the groups of the user's areas, the way back and no dock", %{
      conn: conn,
      user: user
    } do
      olga!(user)
      portfolio_fixture(Scope.for_user(user), %{name: "Langfristig"})

      {:ok, view, _html} = live(conn, ~p"/settings/appearance")

      assert hub(view) == [
               "Allgemein",
               "Zugang",
               "Aussehen",
               "Budget",
               "YNAB-Import",
               "Kasse",
               "Gruppe",
               "Teilnehmer",
               "Kategorien",
               "Wiederkehrende Ausgaben",
               "Wechselkurse",
               "Budget-Verknüpfung",
               "Export",
               "YNAB",
               "Depot",
               "Depots",
               "Belegeingang"
             ]

      assert has_element?(view, ~s|#settings-back-sidebar[href="/budget"]|)
      assert has_element?(view, "#settings-appearance-sidebar[aria-current=page]")
      refute has_element?(view, "#area-finanzen-sidebar")
      refute has_element?(view, ".dock")

      for {id, plush} <- [
            access: "key",
            appearance: "palette",
            ynab_import: "history",
            kasse_group: "house",
            kasse_participants: "users",
            kasse_categories: "tag",
            kasse_recurring: "repeat",
            kasse_rates: "banknote",
            kasse_budget: "link",
            kasse_export: "archive",
            kasse_ynab: "wallet",
            depots: "briefcase",
            receipt_intake: "file-text"
          ] do
        id = id |> Atom.to_string() |> String.replace("_", "-")
        assert has_element?(view, ~s|#settings-#{id}-sidebar img[src^="/images/plush/#{plush}"]|)
      end
    end

    test "leads back to the area used last", %{conn: conn, user: user} do
      olga!(user)
      conn = Plug.Test.init_test_session(conn, area: "kasse")

      {:ok, view, _html} = live(conn, ~p"/settings/appearance")

      assert has_element?(view, ~s|#settings-back-sidebar[href="/kasse"]|, "Zurück zur Kasse")
    end

    test "links within a live_session navigate, the others load the page", %{
      conn: conn,
      user: user
    } do
      olga!(user)

      {:ok, view, _html} = live(conn, ~p"/settings/kasse/categories")

      assert has_element?(view, "#settings-kasse-rates-sidebar[data-phx-link]")
      refute has_element?(view, "#settings-appearance-sidebar[data-phx-link]")
      refute has_element?(view, "#settings-access-sidebar[data-phx-link]")
      assert has_element?(view, "#settings-kasse-categories-sidebar[aria-current=page]")
    end

    test "Zugang holds passkeys and email; Aussehen the theme", %{conn: conn} do
      {:ok, access, _html} = live(conn, ~p"/settings/access")

      assert has_element?(access, "h1", "Zugang")
      assert has_element?(access, "#passkeys")
      assert has_element?(access, "#email-form")
      refute has_element?(access, "#theme-toggle")

      {:ok, appearance, _html} = live(conn, ~p"/settings/appearance")

      assert has_element?(appearance, "h1", "Aussehen")
      assert has_element?(appearance, "#appearance", "Gilt für dieses Gerät")
      assert has_element?(appearance, "#appearance #theme-toggle[phx-hook]")

      for label <- ["System", "Hell", "Dunkel"],
          do: assert(has_element?(appearance, "#theme-toggle label", label))
    end
  end

  describe "a Kasse person without the budget or a portfolio" do
    setup %{conn: conn} do
      dora = person!("Dora")
      %{conn: log_in_participant(conn, dora.id)}
    end

    test "sees Allgemein, the Kasse and the way to a first portfolio", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/settings/appearance")

      assert hub(view) == [
               "Allgemein",
               "Zugang",
               "Aussehen",
               "Kasse",
               "Gruppe",
               "Teilnehmer",
               "Kategorien",
               "Wiederkehrende Ausgaben",
               "Wechselkurse",
               "Export",
               "YNAB",
               "Depot",
               "Depots"
             ]

      assert has_element?(view, ~s|#settings-back-sidebar[href="/kasse"]|, "Zurück zur Kasse")
    end

    test "gets 404 on the Budget's settings and Belegeingang", %{conn: conn} do
      assert_error_sent 404, fn -> get(conn, ~p"/settings/budget/ynab") end
      assert_error_sent 404, fn -> get(conn, ~p"/settings/kasse/budget") end
      assert_error_sent 404, fn -> get(conn, ~p"/settings/depot/receipt-intake") end
    end
  end

  test "the Kasse's settings answer 404 to a user who is no person of the Kasse", %{conn: conn} do
    for %{verb: :get, path: "/settings/kasse" <> _ = path} <- AbakusWeb.Router.__routes__() do
      assert_error_sent 404, fn -> get(conn, path) end
    end
  end

  describe "YNAB import status" do
    test "says when nothing came from YNAB", %{conn: conn} do
      transaction_fixture()

      {:ok, view, _html} = live(conn, ~p"/settings/budget/ynab")

      assert has_element?(view, "#ynab-import", "Noch nichts aus YNAB übernommen.")
      refute has_element?(view, "#ynab-import-summary")
    end

    test "shows when the import ran and what it brought over", %{conn: conn} do
      {:ok, _report} = YnabImport.import_plan(Scope.system(), @plan)
      %{imported_at: imported_at} = YnabImport.status(budget_scope())

      {:ok, view, _html} = live(conn, ~p"/settings/budget/ynab")

      assert has_element?(
               view,
               "#ynab-import",
               "übernommen am #{Calendar.strftime(LocalTime.date(imported_at), "%d.%m.%Y")}"
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
