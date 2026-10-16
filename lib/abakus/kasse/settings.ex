defmodule Abakus.Kasse.Settings do
  @moduledoc "The settings of the group: its name. The functions take the caller's scope."

  alias Abakus.Kasse.{Access, Activities}
  alias Abakus.Kasse.Settings.Setting
  alias Abakus.Repo
  alias Abakus.Users.Scope

  @default_group_name "Kasse"

  @doc "The settings."
  def get_settings(%Scope{} = scope) do
    Access.check!(scope)
    stored()
  end

  defp stored, do: Repo.get(Setting, 1) || %Setting{id: 1, group_name: @default_group_name}

  @doc "The name of the group."
  def group_name(%Scope{} = scope), do: get_settings(scope).group_name

  @doc "A changeset for the settings form."
  def change_settings(%Setting{} = setting, attrs \\ %{}), do: Setting.changeset(setting, attrs)

  @doc "Renames the group; logged only when the name changes."
  def update_settings(%Scope{} = scope, attrs) do
    actor_id = Access.actor_id!(scope)

    Repo.transact(fn ->
      setting = stored()

      with {:ok, updated} <- Repo.insert_or_update(Setting.changeset(setting, attrs)),
           {:ok, _activity} <- log_rename(actor_id, setting.group_name, updated.group_name) do
        {:ok, updated}
      end
    end)
  end

  defp log_rename(_actor_id, same, same), do: {:ok, nil}

  defp log_rename(actor_id, old, new),
    do: Activities.log_settings(actor_id, "Gruppe umbenannt: „#{old}“ → „#{new}“")
end
