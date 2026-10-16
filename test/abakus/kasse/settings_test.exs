defmodule Abakus.Kasse.SettingsTest do
  use Abakus.DataCase

  import Abakus.KasseFixtures

  alias Abakus.Kasse.{Activities, Settings}

  test "the group is called Kasse on a new database" do
    assert Settings.group_name() == "Kasse"
  end

  test "renames the group with collapsed whitespace and logs it with the actor" do
    anna = person!("Anna")
    {:ok, _settings} = Settings.update_settings(anna.id, %{group_name: " WG  Zipfel "})

    assert Settings.group_name() == "WG Zipfel"

    assert [
             %{
               actor_id: actor_id,
               details: %{text: "Gruppe umbenannt: „Kasse“ → „WG Zipfel“"}
             }
             | _
           ] =
             Activities.list_activities()

    assert actor_id == anna.id
  end

  test "logs nothing when the name stays, and refuses an empty one" do
    {:ok, _settings} = Settings.update_settings(nil, %{group_name: "Kasse "})
    assert {:error, changeset} = Settings.update_settings(nil, %{group_name: "  "})

    assert errors_on(changeset) == %{group_name: ["Bitte einen Namen für die Gruppe angeben."]}
    assert Activities.list_activities() == []
  end
end
