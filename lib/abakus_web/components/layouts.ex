defmodule AbakusWeb.Layouts do
  @moduledoc false
  use AbakusWeb, :html

  embed_templates "layouts/*"

  attr :flash, :map, required: true
  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <a class="visually-hidden-focusable btn btn-primary m-2" href="#main">Zum Inhalt springen</a>

    <header class="container d-flex flex-wrap align-items-center gap-2 py-3 mb-2">
      <.link class="fw-bold fs-5 text-decoration-none text-body me-auto" navigate={~p"/"}>
        Abakus
      </.link>
      <.theme_switch />
    </header>

    <main class="container pb-5" id="main">
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
