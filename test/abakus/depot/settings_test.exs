defmodule Abakus.Depot.SettingsTest do
  use Abakus.DataCase

  import Abakus.UsersFixtures

  alias Abakus.Depot.Settings
  alias Abakus.Depot.Settings.Setting

  describe "update_paperless/2" do
    setup do
      scope = user_scope_fixture()

      {:ok, _setting} =
        Settings.update_paperless(scope, %{
          "paperless_url" => "https://paperless.example.org",
          "paperless_token" => "geheim",
          "paperless_tag" => "abakus"
        })

      %{scope: scope}
    end

    test "keeps the stored token for a blank one while the URL stays", %{scope: scope} do
      assert {:ok, %Setting{paperless_token: "geheim", paperless_tag: "belege"}} =
               Settings.update_paperless(scope, %{
                 "paperless_url" => "https://paperless.example.org/",
                 "paperless_token" => " ",
                 "paperless_tag" => "belege"
               })
    end

    test "forgets the last poll when URL or tag change", %{scope: scope} do
      polled = fn -> :ok = Settings.paperless_polled(Settings.get_settings(scope)) end
      polled.()

      assert {:ok, %Setting{paperless_polled_at: %DateTime{}}} =
               Settings.update_paperless(scope, %{"paperless_token" => "neu"})

      assert {:ok, %Setting{paperless_polled_at: nil}} =
               Settings.update_paperless(scope, %{"paperless_tag" => "belege"})

      polled.()

      assert {:ok, %Setting{paperless_polled_at: nil}} =
               Settings.update_paperless(scope, %{
                 "paperless_url" => "https://other.example.org",
                 "paperless_token" => "neu"
               })
    end

    test "refuses a URL without a host", %{scope: scope} do
      for url <- ["http:foo", "https://"] do
        assert {:error, changeset} =
                 Settings.update_paperless(scope, %{
                   "paperless_url" => url,
                   "paperless_token" => "t"
                 })

        assert errors_on(changeset).paperless_url == [
                 "braucht http:// oder https:// und einen Host"
               ]
      end
    end

    test "needs the token entered again for a new URL", %{scope: scope} do
      attrs = %{"paperless_url" => "https://evil.example.org", "paperless_token" => ""}

      assert {:error, changeset} = Settings.update_paperless(scope, attrs)
      assert errors_on(changeset).paperless_token == ["bitte für die neue URL eingeben"]

      assert {:ok, %Setting{paperless_url: "https://evil.example.org"}} =
               Settings.update_paperless(scope, %{attrs | "paperless_token" => "geheim"})
    end

    test "disconnecting forgets URL, token and tag", %{scope: scope} do
      assert {:ok, _setting} = Settings.disconnect_paperless(scope)

      assert %Setting{paperless_url: nil, paperless_token: nil, paperless_tag: nil} =
               Settings.get_settings(scope)
    end
  end

  test "lists only the users who entered a whole Paperless, with the user" do
    scope = user_scope_fixture()
    other = user_scope_fixture()

    {:ok, _setting} =
      Settings.update_paperless(scope, %{
        "paperless_url" => "http://paperless:8000",
        "paperless_token" => "t",
        "paperless_tag" => "abakus"
      })

    {:ok, _setting} = Settings.update_benchmark(other, nil)

    assert [%Setting{user: user}] = Settings.list_paperless()
    assert user.id == scope.user.id
  end
end
