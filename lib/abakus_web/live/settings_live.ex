defmodule AbakusWeb.SettingsLive do
  @moduledoc """
  The settings' section of its own: Aussehen (the theme, per device). Zugang is `AbakusWeb.UserLive.Settings`,
  behind the sudo plug.
  """
  use AbakusWeb, :live_view

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.settings
      current={:appearance}
      flash={@flash}
      current_scope={@current_scope}
      areas={@areas}
      area={@area}
      groups={@settings_groups}
    >
      <.header>{@page_title}</.header>
      <section id="appearance">
        <p class="mb-3 text-sm text-base-content/70">Gilt für dieses Gerät.</p>
        <.theme_toggle />
        <p class="mt-6 max-w-prose text-sm text-base-content/70">
          Als App installieren: im Browser „Zum Home-Bildschirm“ wählen.
        </p>
      </section>
    </Layouts.settings>
    """
  end

  @impl true
  def mount(_params, _session, socket), do: {:ok, assign(socket, :page_title, "Aussehen")}
end
