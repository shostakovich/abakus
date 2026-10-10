defmodule AbakusWeb.SettingsLive.Components do
  @moduledoc """
  The frame of the settings ("Mehr"): the section navigation and one section, as in the dummy. Wide screens show
  the navigation beside the section; phones show the overview or one section with the way back.
  """
  use AbakusWeb, :html

  @sections [
    {:access, "Zugang & API", "key", "Passkeys, E-Mail, API-Tokens"},
    {:appearance, "Aussehen", "palette", "Hell, Dunkel oder automatisch"},
    {:ynab, "YNAB-Import", "history", "Was aus YNAB übernommen wurde"}
  ]

  attr :section, :atom, values: [nil | Enum.map(@sections, &elem(&1, 0))], required: true
  attr :flash, :map, required: true
  attr :current_scope, :map, required: true
  attr :account_groups, :list, required: true
  attr :account_dialog, :map, required: true
  slot :inner_block

  def page(assigns) do
    assigns = assign(assigns, :sections, @sections)

    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      current={:settings}
      account_groups={@account_groups}
      account_dialog={@account_dialog}
    >
      <.link
        :if={@section}
        id="settings-back"
        href={~p"/settings"}
        class="d-inline-flex d-lg-none align-items-center gap-1 small text-decoration-none mb-1"
      >
        <.icon name="back" class="app-icon-sm" /> Einstellungen
      </.link>
      <.header>
        <%= if @section do %>
          <span class="d-lg-none">{label(@section)}</span>
          <span class="d-none d-lg-inline">Einstellungen</span>
        <% else %>
          Einstellungen
        <% end %>
      </.header>

      <div class="row g-4">
        <div class={if @section, do: "col-lg-3 d-none d-lg-block", else: "col-lg-5"}>
          <nav id="settings-nav" class="list-group app-settings-nav" aria-label="Einstellungen">
            <.link
              :for={{key, label, icon, hint} <- @sections}
              href={path(key)}
              class={[
                "list-group-item list-group-item-action d-flex align-items-center gap-3 py-3",
                key == @section && "active"
              ]}
              aria-current={key == @section && "page"}
            >
              <.icon name={icon} />
              <span class="me-auto">
                <span class="d-block fw-semibold">{label}</span>
                <span class="small app-nav-sub">{hint}</span>
              </span>
              <.icon name="chevron" class="app-icon-sm text-body-secondary" />
            </.link>
          </nav>
        </div>
        <div :if={@section} class="col-lg-9 app-settings-content">
          {render_slot(@inner_block)}
        </div>
      </div>
    </Layouts.app>
    """
  end

  @doc "The section's name, e.g. for the page title."
  def label(section) do
    {^section, label, _icon, _hint} = List.keyfind(@sections, section, 0)
    label
  end

  defp path(:access), do: ~p"/settings/access"
  defp path(:appearance), do: ~p"/settings/appearance"
  defp path(:ynab), do: ~p"/settings/ynab"
end
