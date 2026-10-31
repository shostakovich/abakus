defmodule AbakusWeb.DevicesLive do
  @moduledoc "Geräte: the apps the budget owner signed in, each signed out through the confirm dialog."
  use AbakusWeb, :live_view

  alias Abakus.{Devices, Format}
  alias Abakus.Users.Scope

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.settings
      current={:devices}
      flash={@flash}
      current_scope={@current_scope}
      areas={@areas}
      area={@area}
      groups={@settings_groups}
    >
      <.header>Geräte</.header>
      <section id="devices" aria-labelledby="devices-title">
        <.section_heading id="devices-title" count={if @devices != [], do: length(@devices)}>
          Angemeldete Apps
        </.section_heading>
        <p class="mb-3 max-w-prose text-sm text-base-content/70">
          Eine App meldest du in der App selbst an, mit deinem Passkey. Ein abgemeldetes Gerät kann nicht mehr synchronisieren.
        </p>
        <.empty_state :if={@devices == []} plush="smartphone" icon="smartphone">
          Noch keine App angemeldet.
        </.empty_state>
        <.list :if={@devices != []}>
          <.list_row :for={device <- @devices} id={"device-#{device.id}"} title={device.name}>
            <:leading><.icon name="smartphone" class="size-5 text-base-content/70" /></:leading>
            <:meta>
              {device.app}<.meta_sep />angemeldet {Format.date(device.signed_in_at)}<span :if={
                device.last_synced_at
              }><.meta_sep />zuletzt synchronisiert {Format.datetime(device.last_synced_at)}</span>
            </:meta>
            <:action
              id={"device-#{device.id}-sign-out"}
              label="Abmelden"
              icon="log-out"
              danger
              confirm={"„#{device.name}“ abmelden?"}
              on_click={JS.push("sign_out", value: %{id: device.id})}
            />
          </.list_row>
        </.list>
      </section>
    </Layouts.settings>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    if !Scope.budget_owner?(socket.assigns.current_scope), do: raise(AbakusWeb.NotFoundError)
    {:ok, socket |> assign(:page_title, "Geräte") |> assign_devices()}
  end

  @impl true
  def handle_event("sign_out", %{"id" => id}, socket) do
    case Devices.sign_out(socket.assigns.current_scope, id) do
      :ok ->
        {:noreply, socket |> put_flash(:info, "Das Gerät ist abgemeldet.") |> assign_devices()}

      {:error, :not_found} ->
        {:noreply, assign_devices(socket)}
    end
  end

  defp assign_devices(socket),
    do: assign(socket, :devices, Devices.list_devices(socket.assigns.current_scope))
end
