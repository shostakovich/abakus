defmodule Abakus.UsersFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Abakus.Users` context.
  """

  import Ecto.Query

  alias Abakus.Users
  alias Abakus.Users.Scope

  def unique_user_email, do: "user#{System.unique_integer()}@example.com"

  def valid_user_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{
      email: unique_user_email()
    })
  end

  def unconfirmed_user_fixture(attrs \\ %{}) do
    {:ok, user} =
      attrs
      |> valid_user_attributes()
      |> Users.create_user()

    user
  end

  def user_fixture(attrs \\ %{}) do
    user = unconfirmed_user_fixture(attrs)

    token =
      extract_user_token(fn url ->
        Users.deliver_login_instructions(user, url)
      end)

    {:ok, user} = Users.login_user_by_magic_link(token)

    user
  end

  def user_scope_fixture do
    user = user_fixture()
    user_scope_fixture(user)
  end

  def user_scope_fixture(user) do
    Scope.for_user(user)
  end

  def extract_user_token(fun) do
    {:ok, captured_email} = fun.(&"[TOKEN]#{&1}[TOKEN]")
    [_, token | _] = String.split(captured_email.text_body, "[TOKEN]")
    token
  end

  @doc "Registers a passkey of the given fake authenticator for the user."
  def passkey_fixture(user, authenticator \\ Abakus.FakeAuthenticator.new()) do
    challenge = Abakus.WebAuthn.new_challenge()
    response = Abakus.FakeAuthenticator.registration(authenticator, challenge)
    rp = Abakus.FakeAuthenticator.relying_party()

    {:ok, passkey} = Users.register_passkey(user, response, challenge, rp, "Testgerät")
    passkey
  end

  def override_token_authenticated_at(token, authenticated_at) when is_binary(token) do
    Abakus.Repo.update_all(
      from(t in Users.UserToken,
        where: t.token == ^token
      ),
      set: [authenticated_at: authenticated_at]
    )
  end

  def generate_user_magic_link_token(user) do
    {encoded_token, user_token} = Users.UserToken.build_email_token(user, "login")
    Abakus.Repo.insert!(user_token)
    {encoded_token, user_token.token}
  end

  def offset_user_token(token, amount_to_add, unit) do
    dt = DateTime.add(DateTime.utc_now(), amount_to_add, unit)

    Abakus.Repo.update_all(
      from(ut in Users.UserToken, where: ut.token == ^token),
      set: [inserted_at: dt, authenticated_at: dt]
    )
  end
end
