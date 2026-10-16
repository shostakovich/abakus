defmodule AbakusWeb.Kasse.SettingsLiveTest do
  use AbakusWeb.ConnCase

  import Abakus.KasseFixtures

  import Phoenix.LiveViewTest

  alias Abakus.Kasse.{Activities, Settings}

  setup %{conn: conn} do
    anna = person!("Anna")
    %{anna: anna, conn: log_in_participant(conn, anna.id)}
  end

  defp save(view, name),
    do: view |> form("#settings-form", settings: %{group_name: name}) |> render_submit()

  defp renames,
    do: for(a <- Activities.list_activities(), a.details.text =~ "Gruppe", do: a.details.text)

  defp links(view) do
    for link <-
          view |> render() |> LazyHTML.from_fragment() |> LazyHTML.query("#settings-links a") do
      {link |> LazyHTML.attribute("href") |> hd(), link |> LazyHTML.text() |> String.trim()}
    end
  end

  test "links the other settings with their plush, the budget for its owner", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/kasse/settings")

    assert links(view) == [
             {"/kasse/settings/participants", "Teilnehmer"},
             {"/kasse/settings/categories", "Kategorien"},
             {"/kasse/settings/recurring", "Wiederkehrende Ausgaben"},
             {"/kasse/settings/rates", "Wechselkurse"},
             {"/kasse/settings/budget", "Budget"},
             {"/kasse/settings/ynab", "YNAB"},
             {"/kasse/export", "Export"}
           ]

    for plush <- ~w(users tag repeat banknote scale wallet archive),
        do: assert(has_element?(view, ~s(#settings-links img[src^="/images/plush/#{plush}"])))
  end

  test "links no budget for anyone else", %{conn: conn, anna: anna} do
    ben = person!("Ben", anna.id)
    {:ok, view, _html} = live(log_in_participant(conn, ben.id), ~p"/kasse/settings")

    refute {"/kasse/settings/budget", "Budget"} in links(view)
  end

  test "renames the group, logged only when the name changes", %{conn: conn, anna: anna} do
    {:ok, view, _html} = live(conn, ~p"/kasse/settings")
    assert has_element?(view, "#settings_group_name[value=Kasse]")

    save(view, "  WG   Süd ")

    assert_push_event(view, "setzkasten:saved", %{id: "settings-save"})
    assert Settings.group_name() == "WG Süd"
    assert has_element?(view, "#settings_group_name[value='WG Süd']")

    save(view, "WG Süd")

    assert renames() == ["Gruppe umbenannt: „Kasse“ → „WG Süd“"]
    assert hd(Activities.list_activities()).actor_id == anna.id
  end

  test "an empty or long name stays in the field with its error", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/kasse/settings")

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
