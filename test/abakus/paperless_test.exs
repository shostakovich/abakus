defmodule Abakus.PaperlessTest do
  use Abakus.DataCase

  import Abakus.UsersFixtures

  alias Abakus.Paperless
  alias Abakus.Paperless.Connection

  setup do
    scope = user_scope_fixture()

    {:ok, _connection} =
      Paperless.update_connection(scope, %{
        "url" => "https://paperless.example.org",
        "token" => "geheim"
      })

    %{scope: scope}
  end

  test "is the user's own", %{scope: scope} do
    other = user_scope_fixture()

    refute Paperless.connected?(Paperless.get_connection(other))
    assert Paperless.connected?(Paperless.get_connection(scope))
  end

  test "keeps the stored token for a blank one while the URL stays", %{scope: scope} do
    assert {:ok, %Connection{url: "https://paperless.example.org", token: "geheim"}} =
             Paperless.update_connection(scope, %{
               "url" => " https://paperless.example.org/ ",
               "token" => " "
             })
  end

  test "refuses a URL without a host", %{scope: scope} do
    for url <- ["http:foo", "https://", "paperless.local"] do
      assert {:error, changeset} =
               Paperless.update_connection(scope, %{"url" => url, "token" => "t"})

      assert errors_on(changeset).url == ["braucht http:// oder https:// und einen Host"]
    end
  end

  test "needs a URL", %{scope: scope} do
    assert {:error, changeset} = Paperless.update_connection(scope, %{"url" => " "})
    assert errors_on(changeset).url == ["can't be blank"]
  end

  test "needs the token entered again for a new URL", %{scope: scope} do
    attrs = %{"url" => "https://evil.example.org", "token" => ""}

    assert {:error, changeset} = Paperless.update_connection(scope, attrs)
    assert errors_on(changeset).token == ["bitte für die neue URL eingeben"]

    assert {:ok, %Connection{url: "https://evil.example.org", token: "geheim"}} =
             Paperless.update_connection(scope, %{attrs | "token" => "geheim"})
  end

  test "disconnecting forgets URL and token", %{scope: scope} do
    assert {:ok, %Connection{url: nil, token: nil}} = Paperless.disconnect(scope)
    assert %Connection{id: nil, url: nil, token: nil} = Paperless.get_connection(scope)
  end

  test "never shows the token" do
    refute inspect(%Connection{token: "geheim"}) =~ "geheim"
  end
end
