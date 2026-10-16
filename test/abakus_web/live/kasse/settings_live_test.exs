defmodule AbakusWeb.Kasse.SettingsLiveTest do
  use AbakusWeb.ConnCase

  import Abakus.KasseFixtures

  import Phoenix.LiveViewTest

  alias Abakus.Kasse.{Activities, Settings}
  alias Abakus.Users.Scope

  setup %{conn: conn} do
    anna = person!("Anna")
    %{anna: anna, conn: log_in_participant(conn, anna.id)}
  end

  defp save(view, name),
    do: view |> form("#settings-form", settings: %{group_name: name}) |> render_submit()

  defp renames,
    do:
      for(
        a <- Activities.list_activities(Scope.system()),
        a.details.text =~ "Gruppe",
        do: a.details.text
      )

  test "is the Kasse's first section of the settings, no longer in the Kasse's navigation", %{
    conn: conn
  } do
    {:ok, view, _html} = live(conn, ~p"/settings/kasse")

    assert has_element?(view, "h1", "Gruppe")
    assert has_element?(view, "#settings-kasse-group-sidebar[aria-current=page]", "Gruppe")
    assert has_element?(view, "#settings-kasse-budget-sidebar", "Budget-Verknüpfung")

    {:ok, kasse, _html} = live(conn, ~p"/kasse")
    refute has_element?(kasse, sidebar_link("/settings/kasse"))
  end

  test "offers the Budget-Verknüpfung to no one but the budget owner", %{conn: conn, anna: anna} do
    ben = person!("Ben", anna.id)
    {:ok, view, _html} = live(log_in_participant(conn, ben.id), ~p"/settings/kasse")

    refute has_element?(view, "#settings-kasse-budget-sidebar")
  end

  test "renames the group, logged only when the name changes", %{conn: conn, anna: anna} do
    {:ok, view, _html} = live(conn, ~p"/settings/kasse")
    assert has_element?(view, "#settings_group_name[value=Kasse]")

    save(view, "  WG   Süd ")

    assert_push_event(view, "setzkasten:saved", %{id: "settings-save"})
    assert Settings.group_name() == "WG Süd"
    assert has_element?(view, "#settings_group_name[value='WG Süd']")

    save(view, "WG Süd")

    assert renames() == ["Gruppe umbenannt: „Kasse“ → „WG Süd“"]
    assert hd(Activities.list_activities(Scope.system())).actor_id == anna.id
  end

  test "an empty or long name stays in the field with its error", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/settings/kasse")

    save(view, "  ")

    assert has_element?(
             view,
             "#settings_group_name-error-0",
             "Bitte einen Namen für die Gruppe angeben."
           )

    save(view, String.duplicate("y", 61))

    assert has_element?(
             view,
             "#settings_group_name-error-0",
             "Der Name ist zu lang (höchstens 60 Zeichen)."
           )

    assert Settings.group_name() == "Kasse"
    assert renames() == []
  end
end
