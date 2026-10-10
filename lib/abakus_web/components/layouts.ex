defmodule AbakusWeb.Layouts do
  @moduledoc false
  use AbakusWeb, :html

  embed_templates "layouts/*"

  attr :flash, :map, required: true
  attr :current_scope, :map, required: true
  attr :current, :atom, default: nil, values: [nil, :budget, :settings]
  slot :inner_block, required: true

  @doc """
  Signed-in pages: a dark sidebar as in YNAB, collapsible to an icon rail (remembered per device by `SideToggle`);
  phones get a header instead.
  """
  def app(assigns) do
    ~H"""
    <a class="visually-hidden-focusable btn btn-primary m-2 app-skip" href="#main">Zum Inhalt springen</a>

    <aside class="app-side d-none d-lg-flex flex-column" data-bs-theme="dark">
      <div class="dropdown pt-3 pb-2" phx-click-away={hide_dropdown("#side-menu", "#side-brand")}>
        <button
          type="button"
          id="side-brand"
          class="btn w-100 text-start d-flex align-items-center gap-2 border-0 text-reset app-side-brand"
          aria-expanded="false"
          aria-controls="side-menu"
          title={"Abakus · #{@current_scope.user.email}"}
          phx-click={toggle_dropdown("#side-menu", "#side-brand")}
        >
          <img src={~p"/images/icon.svg"} alt="" width="30" height="30" />
          <span class="me-auto lh-sm app-side-text app-min-w-0">
            <span class="d-block fw-bold">Abakus</span>
            <span class="d-block small opacity-75 text-truncate">{@current_scope.user.email}</span>
          </span>
          <.icon name="down" class="app-icon-sm app-side-text" />
        </button>
        <ul id="side-menu" class="dropdown-menu" data-bs-popper="static">
          <li><.link class="dropdown-item" href={~p"/users/settings"}>Einstellungen</.link></li>
          <li><hr class="dropdown-divider" /></li>
          <li>
            <.link
              id="log-out"
              class="dropdown-item"
              href={~p"/users/log-out"}
              method="delete"
              title={@current_scope.user.email}
            >
              Abmelden
            </.link>
          </li>
        </ul>
      </div>
      <nav class="nav flex-column gap-1" aria-label="Hauptnavigation">
        <.side_links items={main_items()} current={@current} />
      </nav>
      <div class="flex-grow-1"></div>
      <nav class="nav flex-column pt-2 border-top" aria-label="Weitere">
        <.side_links items={more_items()} current={@current} />
      </nav>
      <div class="d-flex justify-content-end py-2">
        <button
          type="button"
          id="side-toggle"
          class="btn btn-sm app-side-toggle"
          aria-label="Seitenleiste einklappen"
          title="Seitenleiste einklappen"
          phx-hook="SideToggle"
          phx-update="ignore"
        >
          <.icon name="sidebar" />
        </button>
      </div>
    </aside>

    <header class="d-flex d-lg-none flex-wrap align-items-center gap-2 px-3 pt-3">
      <.link
        class="fw-bold fs-5 text-decoration-none text-body me-auto d-flex align-items-center gap-2"
        {nav_link(~p"/", @current)}
      >
        <img src={~p"/images/icon.svg"} alt="" width="26" height="26" /> Abakus
      </.link>
      <nav aria-label="Hauptnavigation">
        <ul class="nav nav-pills">
          <li :for={{key, label, _icon, path} <- main_items() ++ more_items()} class="nav-item">
            <.link
              class={["nav-link", @current == key && "active"]}
              aria-current={@current == key && "page"}
              {nav_link(path, @current)}
            >
              {label}
            </.link>
          </li>
        </ul>
      </nav>
      <.link href={~p"/users/log-out"} method="delete" class="btn btn-sm btn-outline-secondary">
        Abmelden
      </.link>
    </header>

    <main class="app container-fluid px-3" id="main">
      <.flash_group flash={@flash} />
      {render_slot(@inner_block)}
    </main>
    """
  end

  attr :items, :list, required: true
  attr :current, :atom, required: true

  defp side_links(assigns) do
    ~H"""
    <.link
      :for={{key, label, icon, path} <- @items}
      class={["nav-link", @current == key && "active"]}
      aria-current={@current == key && "page"}
      title={label}
      {nav_link(path, @current)}
    >
      <.icon name={icon} /><span class="app-side-text">{label}</span>
    </.link>
    """
  end

  defp main_items, do: [{:budget, "Budget", "budget", ~p"/"}]
  defp more_items, do: [{:settings, "Einstellungen", "gear", ~p"/users/settings"}]

  # The settings have a live_session of their own behind the sudo plug, so links into and out
  # of them load the page.
  defp nav_link(path, current) do
    if path == ~p"/users/settings" or current == :settings,
      do: [href: path],
      else: [navigate: path]
  end

  attr :flash, :map, required: true
  slot :inner_block, required: true

  @doc "Sign-in pages: a narrow column without navigation."
  def auth(assigns) do
    ~H"""
    <main class="container px-3 py-5 app-auth" id="main">
      <h1 class="h3 fw-bold text-center mb-4">Abakus</h1>
      <.flash_group flash={@flash} />
      {render_slot(@inner_block)}
    </main>
    """
  end

  @doc "Light, dark or the device's setting; remembered per device by the `ThemeSwitch` hook."
  def theme_switch(assigns) do
    ~H"""
    <div
      id="theme-switch"
      class="btn-group btn-group-sm"
      role="group"
      aria-label="Farbschema"
      phx-hook="ThemeSwitch"
      phx-update="ignore"
    >
      <%= for {value, label} <- [{"light", "Hell"}, {"dark", "Dunkel"}, {"auto", "Auto"}] do %>
        <input type="radio" class="btn-check" name="theme" id={"theme-#{value}"} value={value} />
        <label class="btn btn-outline-primary" for={"theme-#{value}"}>{label}</label>
      <% end %>
    </div>
    """
  end
end
