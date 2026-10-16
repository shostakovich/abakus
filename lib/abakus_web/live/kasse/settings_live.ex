defmodule AbakusWeb.Kasse.SettingsLive do
  @moduledoc """
  "Gruppe", the first of the Kasse's settings: the group's name.
  """
  use AbakusWeb, :kasse_live_view

  alias Abakus.Kasse.Settings

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(page_title: "Gruppe")
     |> assign_form(Settings.change_settings(Settings.get_settings()))}
  end

  @impl true
  def handle_event("validate", %{"settings" => params}, socket) do
    changeset = Settings.change_settings(Settings.get_settings(), params)
    {:noreply, assign_form(socket, Map.put(changeset, :action, :validate))}
  end

  def handle_event("save", %{"settings" => params}, socket) do
    case Settings.update_settings(socket.assigns.current_participant.id, params) do
      {:ok, setting} ->
        {:noreply,
         socket
         |> assign(page_title: "Gruppe")
         |> assign_form(Settings.change_settings(setting))
         |> push_saved("settings-save")}

      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp assign_form(socket, changeset), do: assign(socket, form: to_form(changeset, as: :settings))

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.settings
      current={:kasse_group}
      flash={@flash}
      current_scope={@current_scope}
      areas={@areas}
      area={@area}
      groups={@settings_groups}
    >
      <.header>Gruppe</.header>

      <.form for={@form} id="settings-form" phx-change="validate" phx-submit="save">
        <.input
          field={@form[:group_name]}
          label="Name der Gruppe"
          required
          maxlength={Abakus.Kasse.Names.max_length()}
          autocomplete="off"
          inline
        >
          <.button
            id="settings-save"
            type="submit"
            variant={:primary}
            saved
            phx-disable-with="Speichert …"
            class="join-item"
          >
            Speichern
          </.button>
        </.input>
      </.form>
    </Layouts.settings>
    """
  end
end
