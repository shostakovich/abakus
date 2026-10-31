defmodule Abakus.Devices do
  @moduledoc """
  The apps the budget owner signs in (ADR 0026, `sync/PROTOCOL.md`): Abakus is the OAuth 2.1 authorization server of
  its one public client, the Apple apps, with the authorization code flow and PKCE (S256 only). Confirming the sign-in
  creates the device and an authorization code, single use and valid for 60 seconds; exchanging it with its verifier
  signs the device in with an access token for an hour and a refresh token for 90 days, which rotates on every use.
  Reusing a rotated refresh token signs the device out, as someone else may hold it. Tokens are stored hashed
  (`Abakus.Users.UserToken`). Only the budget owner signs apps in and syncs (ADR 0007).
  """

  import Ecto.Query

  alias Abakus.Devices.Device
  alias Abakus.{Ids, Repo, Users}
  alias Abakus.Users.{Scope, User, UserToken}

  @client_id "abakus-apple"
  @client %{
    id: @client_id,
    name: "Abakus-App",
    redirect_uri: "local.abakus:/oauth/callback"
  }

  @challenge ~r/\A[A-Za-z0-9_-]{43}\z/
  @verifier ~r/\A[A-Za-z0-9._~-]{43,128}\z/

  @doc "The registered client with this id, nil for none."
  def client(@client_id), do: @client
  def client(_id), do: nil

  @doc "Whether `challenge` is a PKCE S256 challenge: the unpadded base64url of a SHA-256 hash."
  def code_challenge?(challenge), do: is_binary(challenge) and challenge =~ @challenge

  @doc """
  Signs the device `name` in for `client` once its code is exchanged with the verifier of `code_challenge`:
  `{:ok, code}`, `{:error, :not_owner}` unless the scope's user owns the budget, `{:error, :invalid_challenge}` or
  `{:error, changeset}` for a bad name.
  """
  def authorize(%Scope{user: %User{} = user} = scope, %{id: client_id}, name, code_challenge) do
    cond do
      not Scope.budget_owner?(scope) ->
        {:error, :not_owner}

      not code_challenge?(code_challenge) ->
        {:error, :invalid_challenge}

      true ->
        Users.delete_expired_user_tokens(user)
        Repo.transact(fn -> create_code(user, client(client_id), name, code_challenge) end)
    end
  end

  defp create_code(user, client, name, code_challenge) do
    with {:ok, device} <- create_device(user, client, name) do
      {code, token} = UserToken.build_app_token(device, "app_code", code_challenge)
      Repo.insert!(token)
      {:ok, code}
    end
  end

  defp create_device(user, client, name) do
    %Device{user_id: user.id, app: client.name}
    |> Device.create_changeset(%{name: name})
    |> Repo.insert()
  end

  @doc """
  Exchanges an authorization code with its PKCE verifier for the device's tokens: `{:ok, tokens}` with
  `access_token`, `refresh_token`, `expires_in` and `device_id`, else `{:error, :invalid_grant}`. A code is used up
  by its first exchange, which signs the device out again when it fails.
  """
  def exchange_code(client_id, code, verifier) when is_binary(code) and is_binary(verifier) do
    Repo.transact(fn ->
      with %UserToken{} = token <- take_code(code),
           device = Repo.get!(Device, token.device_id),
           :ok <- check_code(token, client_id, verifier) do
        device
        |> Ecto.Changeset.change(signed_in_at: DateTime.utc_now())
        |> Repo.update!()
        |> issue_tokens()
      else
        nil -> {:error, :invalid_grant}
        {:error, device_id} -> sign_out_device(device_id)
      end
    end)
    |> invalid_grant_on_sign_out()
  end

  def exchange_code(_client_id, _code, _verifier), do: {:error, :invalid_grant}

  defp take_code(code) do
    with {:ok, query} <- UserToken.verify_app_token_query(code, ["app_code"]),
         %UserToken{id: id} = token <- Repo.one(query),
         {1, _deleted} <- Repo.delete_all(from t in UserToken, where: t.id == ^id) do
      token
    else
      _missing -> nil
    end
  end

  defp check_code(token, client_id, verifier) do
    if client(client_id) && verifier =~ @verifier && owner?(token.user_id) &&
         Plug.Crypto.secure_compare(challenge(verifier), token.code_challenge),
       do: :ok,
       else: {:error, token.device_id}
  end

  defp challenge(verifier),
    do: Base.url_encode64(:crypto.hash(:sha256, verifier), padding: false)

  defp owner?(user_id),
    do: Repo.exists?(from u in User, where: u.id == ^user_id and u.budget_owner)

  @doc """
  Rotates a refresh token: `{:ok, tokens}` as `exchange_code/3` gives them, the device's earlier access tokens no
  longer valid; else `{:error, :invalid_grant}`, and a rotated token used again signs its device out.
  """
  def refresh(client_id, refresh_token) when is_binary(refresh_token) do
    Repo.transact(fn ->
      case find_refresh_token(refresh_token) do
        {:ok, token} -> rotate(token, client_id)
        {:reused, device_id} -> sign_out_device(device_id)
        :error -> {:error, :invalid_grant}
      end
    end)
    |> invalid_grant_on_sign_out()
  end

  def refresh(_client_id, _refresh_token), do: {:error, :invalid_grant}

  defp find_refresh_token(refresh_token) do
    with {:ok, query} <-
           UserToken.verify_app_token_query(refresh_token, ["app_refresh", "app_refresh_used"]),
         %UserToken{} = token <- Repo.one(query) do
      if token.context == "app_refresh", do: {:ok, token}, else: {:reused, token.device_id}
    else
      _missing -> :error
    end
  end

  defp rotate(token, client_id) do
    cond do
      client(client_id) == nil or not owner?(token.user_id) ->
        {:error, :invalid_grant}

      used_up?(token) ->
        Repo.delete_all(
          from t in UserToken,
            where: t.device_id == ^token.device_id and t.context == "app_access"
        )

        Device |> Repo.get!(token.device_id) |> issue_tokens()

      true ->
        sign_out_device(token.device_id)
    end
  end

  # Only one of two refreshes with the same token gets to use it up; the other counts as its reuse.
  defp used_up?(token) do
    {count, _rotated} =
      Repo.update_all(
        from(t in UserToken, where: t.id == ^token.id and t.context == "app_refresh"),
        set: [context: "app_refresh_used"]
      )

    count == 1
  end

  defp issue_tokens(device) do
    {access, access_token} = UserToken.build_app_token(device, "app_access")
    {refresh, refresh_token} = UserToken.build_app_token(device, "app_refresh")
    Repo.insert!(access_token)
    Repo.insert!(refresh_token)

    {:ok,
     %{
       access_token: access,
       refresh_token: refresh,
       expires_in: UserToken.app_access_validity_in_seconds(),
       device_id: device.id
     }}
  end

  defp sign_out_device(device_id) do
    Repo.delete_all(from d in Device, where: d.id == ^device_id)
    {:ok, :signed_out}
  end

  defp invalid_grant_on_sign_out({:ok, :signed_out}), do: {:error, :invalid_grant}
  defp invalid_grant_on_sign_out(result), do: result

  @doc "Signs out the device of an access or refresh token, for the app's own sign-out; any other token is ignored."
  def revoke(token) when is_binary(token) do
    with {:ok, query} <-
           UserToken.verify_app_token_query(token, [
             "app_access",
             "app_refresh",
             "app_refresh_used"
           ]),
         %UserToken{device_id: device_id} <- Repo.one(query) do
      sign_out_device(device_id)
    end

    :ok
  end

  def revoke(_token), do: :ok

  @doc "The budget owner's scope and device of a valid access token, else `:error`."
  def authenticate(access_token) when is_binary(access_token) do
    with {:ok, query} <- UserToken.verify_app_token_query(access_token, ["app_access"]),
         {%User{} = user, %Device{} = device} <-
           Repo.one(
             from t in query,
               join: d in assoc(t, :device),
               join: u in assoc(t, :user),
               where: u.budget_owner and not is_nil(d.signed_in_at),
               select: {u, d}
           ) do
      {:ok, Scope.for_user(user), device}
    else
      _invalid -> :error
    end
  end

  def authenticate(_access_token), do: :error

  @doc "Whether the device is still signed in."
  def signed_in?(%Device{id: id}),
    do: Repo.exists?(from d in Device, where: d.id == ^id and not is_nil(d.signed_in_at))

  @doc "Notes that the device has just synced."
  def synced(%Device{id: id}) do
    Repo.update_all(from(d in Device, where: d.id == ^id),
      set: [last_synced_at: DateTime.utc_now()]
    )

    :ok
  end

  @doc "The user's signed-in devices whose refresh token is still valid, the newest sign-in first."
  def list_devices(%Scope{user: %User{id: user_id}}) do
    refreshable =
      from t in UserToken,
        where: t.device_id == parent_as(:device).id and t.context == "app_refresh",
        where: t.inserted_at > ago(^UserToken.app_refresh_validity_in_days(), "day")

    Repo.all(
      from d in Device,
        as: :device,
        where: d.user_id == ^user_id and not is_nil(d.signed_in_at),
        where: exists(refreshable),
        order_by: [desc: d.signed_in_at, desc: d.id]
    )
  end

  @doc "Signs one of the user's devices out; its tokens stop working at once."
  def sign_out(%Scope{user: %User{id: user_id}}, id) do
    with {:ok, id} <- Ids.cast(id),
         {1, _deleted} <-
           Repo.delete_all(from d in Device, where: d.id == ^id and d.user_id == ^user_id) do
      :ok
    else
      _missing -> {:error, :not_found}
    end
  end

  @doc "Deletes the user's devices that hold no code or refresh token any more."
  def delete_stale(user_id) do
    alive =
      from t in UserToken,
        where: t.device_id == parent_as(:device).id and t.context in ["app_code", "app_refresh"]

    Repo.delete_all(
      from d in Device, as: :device, where: d.user_id == ^user_id and not exists(alive)
    )

    :ok
  end
end
