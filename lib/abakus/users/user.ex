defmodule Abakus.Users.User do
  @moduledoc false
  use Abakus.Schema

  import Ecto.Changeset

  schema "users" do
    field :email, :string
    # The WebAuthn user handle: random, so passkeys reveal nothing about the user.
    field :passkey_handle, :binary, redact: true
    field :confirmed_at, :utc_datetime_usec
    field :authenticated_at, :utc_datetime_usec, virtual: true

    has_many :passkeys, Abakus.Users.Passkey

    timestamps()
  end

  def create_changeset(user, attrs) do
    user
    |> email_changeset(attrs)
    |> put_change(:passkey_handle, :crypto.strong_rand_bytes(16))
  end

  @doc """
  A changeset for creating a user or changing the email; the email has to change.

  `validate_unique: false` skips the database check, e.g. for live validation.
  """
  def email_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:email])
    |> validate_email(opts)
  end

  defp validate_email(changeset, opts) do
    changeset =
      changeset
      |> update_change(:email, &normalize_email/1)
      |> validate_required([:email])
      |> validate_format(:email, ~r/^[^@,;\s]+@[^@,;\s]+$/,
        message: "braucht ein @ und keine Leerzeichen"
      )
      |> validate_length(:email, max: 160)

    if Keyword.get(opts, :validate_unique, true) do
      changeset
      |> unsafe_validate_unique(:email, Abakus.Repo)
      |> unique_constraint(:email)
      |> validate_email_changed()
    else
      changeset
    end
  end

  defp validate_email_changed(changeset) do
    if get_field(changeset, :email) && get_change(changeset, :email) == nil do
      add_error(changeset, :email, "ist unverändert")
    else
      changeset
    end
  end

  @doc "Trimmed and in lower case, so lookups do not depend on SQLite's ASCII-only NOCASE."
  def normalize_email(email), do: email |> String.trim() |> String.downcase()

  def confirm_changeset(user), do: change(user, confirmed_at: DateTime.utc_now())
end
