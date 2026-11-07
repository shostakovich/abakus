defmodule Abakus.Depot.SettingsTest do
  use Abakus.DataCase

  import Abakus.UsersFixtures

  alias Abakus.Depot.Settings
  alias Abakus.Depot.Settings.Setting
  alias Abakus.Paperless

  defp connect(scope),
    do:
      {:ok, _connection} =
        Paperless.update_connection(scope, %{"url" => "http://paperless:8000", "token" => "t"})

  describe "update_paperless_tag/2" do
    setup do
      scope = user_scope_fixture()
      {:ok, _setting} = Settings.update_paperless_tag(scope, %{"paperless_tag" => " abakus "})
      %{scope: scope}
    end

    test "trims the tag and takes a blank one for none", %{scope: scope} do
      assert Settings.get_settings(scope).paperless_tag == "abakus"

      assert {:ok, %Setting{paperless_tag: nil}} =
               Settings.update_paperless_tag(scope, %{"paperless_tag" => " "})
    end

    test "forgets the last poll when the tag changes", %{scope: scope} do
      :ok = Settings.paperless_polled(Settings.get_settings(scope))

      assert {:ok, %Setting{paperless_polled_at: %DateTime{}}} =
               Settings.update_paperless_tag(scope, %{"paperless_tag" => "abakus"})

      assert {:ok, %Setting{paperless_polled_at: nil}} =
               Settings.update_paperless_tag(scope, %{"paperless_tag" => "belege"})
    end
  end

  test "lists only the users with a tag and a Paperless connection, with the user" do
    scope = user_scope_fixture()
    untagged = user_scope_fixture()
    unconnected = user_scope_fixture()

    for scope <- [scope, untagged], do: connect(scope)

    for scope <- [scope, unconnected],
        do: {:ok, _setting} = Settings.update_paperless_tag(scope, %{"paperless_tag" => "abakus"})

    {:ok, _setting} = Settings.update_benchmark(untagged, nil)

    assert [%Setting{user: user}] = Settings.list_paperless()
    assert user.id == scope.user.id
  end
end
