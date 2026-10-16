defmodule Abakus.Kasse.SettingsTest do
  use Abakus.DataCase

  import Abakus.KasseFixtures
  import Abakus.UsersFixtures

  alias Abakus.Kasse.{AccessError, Activities, Settings}
  alias Abakus.Users.Scope

  test "the group is called Kasse on a new database" do
    assert Settings.group_name(Scope.system()) == "Kasse"
  end

  test "renames the group with collapsed whitespace and logs it with the actor" do
    anna = person!("Anna")
    {:ok, _settings} = Settings.update_settings(scope_of(anna.id), %{group_name: " WG  Zipfel "})

    assert Settings.group_name(Scope.system()) == "WG Zipfel"

    assert [
             %{
               actor_id: actor_id,
               details: %{text: "Gruppe umbenannt: „Kasse“ → „WG Zipfel“"}
             }
             | _
           ] =
             Activities.list_activities(Scope.system())

    assert actor_id == anna.id
  end

  test "refuses a signed-in user who is not a person" do
    outsider = Scope.for_user(user_fixture())

    assert_raise AccessError, fn -> Settings.get_settings(outsider) end
    assert_raise AccessError, fn -> Settings.update_settings(outsider, %{group_name: "WG"}) end
    assert Settings.group_name(Scope.system()) == "Kasse"
  end

  test "logs nothing when the name stays, and refuses an empty one" do
    {:ok, _settings} = Settings.update_settings(Scope.system(), %{group_name: "Kasse "})
    assert {:error, changeset} = Settings.update_settings(Scope.system(), %{group_name: "  "})

    assert errors_on(changeset) == %{group_name: ["Bitte einen Namen für die Gruppe angeben."]}
    assert Activities.list_activities(Scope.system()) == []
  end
end
