defmodule Abakus.Kasse.Settings.Setting do
  @moduledoc "The settings of the group, a single row."

  use Abakus.Schema

  import Ecto.Changeset

  alias Abakus.Kasse.Names

  @primary_key {:id, :integer, autogenerate: false}
  schema "kasse_settings" do
    field :group_name, :string

    timestamps()
  end

  @doc "A new group name."
  def changeset(setting, attrs) do
    setting
    |> cast(attrs, [:group_name])
    |> Names.validate(:group_name, "die Gruppe")
  end
end
