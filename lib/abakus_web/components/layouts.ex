defmodule AbakusWeb.Layouts do
  @moduledoc false
  use AbakusWeb, :html

  embed_templates "layouts/*"

  attr :flash, :map, required: true
  attr :current_scope, :map, required: true
  attr :current, :atom, default: nil, values: [nil, :budget, :settings]
  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <a class="visually-hidden-focusable btn btn-primary m-2" href="#main">Zum Inhalt springen</a>

    <header class="container d-flex flex-wrap align-items-center gap-2 py-3 mb-2">
      <.link class="fw-bold fs-5 text-decoration-none text-body me-2" {nav_link(~p"/", @current)}>
        Abakus
      </.link>
      <nav class="me-auto" aria-label="Hauptnavigation">
        <ul class="nav nav-pills">
          <li :for={{key, label, path} <- nav_items()} class="nav-item">
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
      <.theme_switch />
      <.link
        id="log-out"
        href={~p"/users/log-out"}
        method="delete"
        class="btn btn-sm btn-outline-secondary"
        title={@current_scope.user.email}
      >
        Abmelden
      </.link>
    </header>

    <main class="container pb-5" id="main">
      <.flash_group flash={@flash} />
      {render_slot(@inner_block)}
    </main>
    """
  end

  defp nav_items,
    do: [{:budget, "Budget", ~p"/"}, {:settings, "Einstellungen", ~p"/users/settings"}]

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
