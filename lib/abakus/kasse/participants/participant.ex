defmodule Abakus.Kasse.Participants.Participant do
  @moduledoc """
  A person of the group, signed in as a user (ADR 0008); a user is at most one person. People are archived,
  never deleted: old expenses keep them.
  """

  use Abakus.Schema

  import Ecto.Changeset

  alias Abakus.Kasse.Names
  alias Abakus.Users.User

  schema "kasse_participants" do
    field :name, :string
    field :email, :string, virtual: true
    field :archived_at, :utc_datetime_usec

    belongs_to :user, User

    timestamps()
  end

  @doc "A new person: name and the email address of their user."
  def create_changeset(participant, attrs) do
    participant
    |> cast(attrs, [:email])
    |> update_change(:email, &User.normalize_email/1)
    |> validate_required(:email, message: "Bitte eine E-Mail-Adresse angeben.")
    |> unique_constraint(:user_id,
      error_key: :email,
      message: "Diese Adresse gehört schon zu einer Person."
    )
    |> changeset(attrs)
  end

  @doc "A new name; unique regardless of case."
  def changeset(participant, attrs) do
    changeset =
      participant
      |> cast(attrs, [:name])
      |> Names.validate(:name, "die Person")

    unique_constraint(changeset, :name,
      message: "„#{get_field(changeset, :name)}“ gibt es schon."
    )
  end

  @doc "Whether the person is archived."
  def archived?(%__MODULE__{archived_at: archived_at}), do: not is_nil(archived_at)
end
