defmodule Abakus.Devices.Device do
  @moduledoc """
  One sign-in of an app: the device's name, the app, when it was signed in and last synced. Its id is the device in
  the clocks of its messages (`sync/PROTOCOL.md`). Until its authorization code is exchanged it is not signed in.
  """
  use Abakus.Schema, uuid: true

  import Ecto.Changeset

  schema "devices" do
    field :name, :string
    field :app, :string
    field :signed_in_at, :utc_datetime_usec
    field :last_synced_at, :utc_datetime_usec

    belongs_to :user, Abakus.Users.User, type: :id
    has_many :tokens, Abakus.Users.UserToken

    timestamps()
  end

  def create_changeset(device, attrs) do
    device
    |> cast(attrs, [:name])
    |> update_change(:name, &String.trim/1)
    |> validate_required([:name])
    |> validate_length(:name, max: 60)
  end
end
