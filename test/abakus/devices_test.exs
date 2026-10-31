defmodule Abakus.DevicesTest do
  use Abakus.DataCase

  import Abakus.DevicesFixtures
  import Abakus.DomainFixtures

  alias Abakus.{Devices, Users, UsersFixtures}
  alias Abakus.Devices.Device
  alias Abakus.Users.{Scope, UserToken}

  setup do
    %{scope: budget_scope()}
  end

  defp backdate(context, seconds) do
    Repo.update_all(from(t in UserToken, where: t.context == ^context),
      set: [inserted_at: DateTime.add(DateTime.utc_now(), -seconds)]
    )
  end

  describe "authorize/4" do
    test "creates a device not yet signed in and a code for it", c do
      assert {:ok, code} =
               Devices.authorize(c.scope, client(), " MacBook ", challenge(verifier()))

      assert is_binary(code)
      assert [%Device{name: "MacBook", app: "Abakus-App", signed_in_at: nil}] = Repo.all(Device)
      assert Devices.list_devices(c.scope) == []
    end

    test "only for the budget owner, with an S256 challenge and a name", c do
      other = Scope.for_user(UsersFixtures.user_fixture())

      assert Devices.authorize(other, client(), "MacBook", challenge(verifier())) ==
               {:error, :not_owner}

      assert Devices.authorize(c.scope, client(), "MacBook", "plain") ==
               {:error, :invalid_challenge}

      assert {:error, %Ecto.Changeset{}} =
               Devices.authorize(c.scope, client(), " ", challenge(verifier()))

      assert Repo.all(Device) == []
    end
  end

  describe "exchange_code/3" do
    test "signs the device in with tokens stored hashed", c do
      verifier = verifier()
      {:ok, code} = Devices.authorize(c.scope, client(), "MacBook", challenge(verifier))

      assert {:ok,
              %{access_token: access, refresh_token: refresh, expires_in: 3600, device_id: id}} =
               Devices.exchange_code(client().id, code, verifier)

      assert %Device{signed_in_at: %DateTime{}} = Repo.get!(Device, id)
      assert {:ok, %Scope{user: %{id: user_id}}, %Device{id: ^id}} = Devices.authenticate(access)
      assert user_id == c.scope.user.id

      stored = Repo.all(from t in UserToken, where: t.device_id == ^id, select: t.token)
      refute Enum.any?(stored, &(&1 in [access, refresh, code]))
    end

    test "uses the code up, and a failed exchange signs the device out", c do
      verifier = verifier()
      {:ok, code} = Devices.authorize(c.scope, client(), "MacBook", challenge(verifier))

      assert Devices.exchange_code(client().id, code, verifier()) == {:error, :invalid_grant}
      assert Devices.exchange_code(client().id, code, verifier) == {:error, :invalid_grant}
      assert Repo.all(Device) == []
    end

    test "refuses a code older than 60 seconds, another client and a user no longer owner", c do
      for {break, client_id} <- [
            {fn -> backdate("app_code", 61) end, client().id},
            {fn -> :ok end, "someone-else"},
            {fn -> Repo.update_all(Abakus.Users.User, set: [budget_owner: false]) end,
             client().id}
          ] do
        verifier = verifier()
        {:ok, code} = Devices.authorize(c.scope, client(), "MacBook", challenge(verifier))
        break.()

        assert Devices.exchange_code(client_id, code, verifier) == {:error, :invalid_grant}
      end
    end
  end

  describe "refresh/2" do
    test "rotates the refresh token and ends the earlier access token", c do
      first = sign_in_device(c.scope)

      assert {:ok, second} = Devices.refresh(client().id, first.refresh_token)
      assert second.device_id == first.device_id
      assert Devices.authenticate(first.access_token) == :error
      assert {:ok, _scope, _device} = Devices.authenticate(second.access_token)
      assert {:ok, _third} = Devices.refresh(client().id, second.refresh_token)
    end

    test "a rotated refresh token used again signs the device out", c do
      first = sign_in_device(c.scope)
      {:ok, second} = Devices.refresh(client().id, first.refresh_token)

      assert Devices.refresh(client().id, first.refresh_token) == {:error, :invalid_grant}
      assert Devices.authenticate(second.access_token) == :error
      assert Devices.refresh(client().id, second.refresh_token) == {:error, :invalid_grant}
      assert Repo.all(Device) == []
    end

    test "refuses a refresh token older than 90 days and an unknown one", c do
      tokens = sign_in_device(c.scope)
      backdate("app_refresh", 90 * 24 * 60 * 60 + 1)

      assert Devices.refresh(client().id, tokens.refresh_token) == {:error, :invalid_grant}
      assert Devices.refresh(client().id, "nix") == {:error, :invalid_grant}
    end
  end

  test "an access token ends after an hour", c do
    tokens = sign_in_device(c.scope)
    backdate("app_access", 3601)

    assert Devices.authenticate(tokens.access_token) == :error
  end

  test "revoke/1 signs the device of an access or refresh token out", c do
    one = sign_in_device(c.scope, "MacBook")
    other = sign_in_device(c.scope, "iPhone")

    assert Devices.revoke(one.refresh_token) == :ok
    assert Devices.revoke(other.access_token) == :ok
    assert Devices.revoke("nix") == :ok
    assert Repo.all(Device) == []
  end

  describe "list_devices/1 and sign_out/2" do
    test "list the user's signed-in devices, newest first, and sign one out", c do
      older = sign_in_device(c.scope, "MacBook")
      newer = sign_in_device(c.scope, "iPhone")
      {:ok, _pending} = Devices.authorize(c.scope, client(), "iPad", challenge(verifier()))
      other = Scope.for_user(UsersFixtures.user_fixture())

      assert Enum.map(Devices.list_devices(c.scope), & &1.name) == ["iPhone", "MacBook"]
      assert Devices.list_devices(other) == []

      assert Devices.sign_out(other, older.device_id) == {:error, :not_found}
      assert Devices.sign_out(c.scope, older.device_id) == :ok
      assert Devices.sign_out(c.scope, "nix") == {:error, :not_found}
      assert Devices.authenticate(older.access_token) == :error
      assert [%Device{id: id}] = Devices.list_devices(c.scope)
      assert id == newer.device_id
    end

    test "a device whose refresh token ran out is no longer listed and goes with the expired tokens",
         c do
      sign_in_device(c.scope)
      {:ok, _pending} = Devices.authorize(c.scope, client(), "iPad", challenge(verifier()))
      backdate("app_refresh", 90 * 24 * 60 * 60 + 1)
      backdate("app_code", 61)

      assert Devices.list_devices(c.scope) == []
      Users.delete_expired_user_tokens(c.scope.user)
      assert Repo.all(Device) == []
    end
  end

  test "synced/1 notes when the device last synced", c do
    tokens = sign_in_device(c.scope)
    device = Repo.get!(Device, tokens.device_id)

    assert Devices.synced(device) == :ok
    assert %DateTime{} = Repo.reload(device).last_synced_at
  end
end
