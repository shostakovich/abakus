defmodule Abakus.Users.Passkey do
  @moduledoc """
  A WebAuthn credential: the public key as SPKI and its COSE algorithm, and whether the
  authenticator may back it up (synced passkeys), which every sign-in has to repeat.
  """
  use Abakus.Schema

  import Ecto.Changeset

  schema "user_passkeys" do
    field :credential_id, :binary
    field :public_key, :binary
    field :algorithm, :integer
    field :sign_count, :integer
    field :backup_eligible, :boolean
    field :name, :string
    field :last_used_at, :utc_datetime_usec

    belongs_to :user, Abakus.Users.User

    timestamps()
  end

  def create_changeset(passkey, attrs) do
    passkey
    |> cast(attrs, [:credential_id, :public_key, :algorithm, :sign_count, :backup_eligible, :name])
    |> update_change(:name, &String.trim/1)
    |> validate_required([
      :credential_id,
      :public_key,
      :algorithm,
      :sign_count,
      :backup_eligible,
      :name
    ])
    |> validate_length(:name, max: 60)
    |> validate_change(:name, &visible_name/2)
    |> unique_constraint(:credential_id)
  end

  @doc "`nil` for a valid name, otherwise what to tell the user."
  def name_error(name) do
    errors = Keyword.get_values(create_changeset(%__MODULE__{}, %{name: name}).errors, :name)

    cond do
      errors == [] ->
        nil

      Enum.any?(errors, fn {_message, opts} -> opts[:validation] == :visible end) ->
        "Der Name darf keine Steuer- oder unsichtbaren Zeichen enthalten."

      true ->
        "Bitte gib dem Passkey einen Namen (höchstens 60 Zeichen)."
    end
  end

  # A joiner between two emoji (after a variation selector or skin tone) builds one emoji.
  @emoji_joiner ~r/(?<=[\p{Extended_Pictographic}\x{FE0F}\x{1F3FB}-\x{1F3FF}])\x{200D}(?=\p{Extended_Pictographic})/u
  @invisible ~r/[\p{C}\p{Zl}\p{Zp}]/u
  @invisible_message "darf keine Steuer- oder unsichtbaren Zeichen enthalten"

  # The name goes into a mail subject and the log, so nothing in it may hide or reorder text.
  defp visible_name(:name, name) do
    if visible?(name), do: [], else: [name: {@invisible_message, validation: :visible}]
  end

  defp visible?(name) do
    String.valid?(name) and
      not String.match?(String.replace(name, @emoji_joiner, ""), @invisible)
  end

  def use_changeset(passkey, sign_count),
    do: change(passkey, sign_count: sign_count, last_used_at: DateTime.utc_now())
end
