defmodule AbakusWeb.Kasse.SettingsLive do
  @moduledoc """
  "Gruppe", the Kasse's settings: the group's name and the way to its people, categories, recurring expenses,
  exchange rates, the budget (for its owner only), YNAB and export.
  """
  use AbakusWeb, :kasse_live_view

  alias Abakus.Kasse.Settings

  @links [
    {"participants", "Teilnehmer", "users", "/kasse/settings/participants"},
    {"categories", "Kategorien", "tag", "/kasse/settings/categories"},
    {"recurring", "Wiederkehrende Ausgaben", "repeat", "/kasse/settings/recurring"},
    {"rates", "Wechselkurse", "banknote", "/kasse/settings/rates"},
    {"budget", "Budget", "scale", "/kasse/settings/budget"},
    {"ynab", "YNAB", "wallet", "/kasse/settings/ynab"},
    {"export", "Export", "archive", "/kasse/export"}
  ]

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(page_title: "Gruppe", links: links(socket.assigns.current_scope.user))
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

  defp links(%{budget_owner: true}), do: @links
  defp links(_user), do: Enum.reject(@links, &(elem(&1, 0) == "budget"))

  defp assign_form(socket, changeset), do: assign(socket, form: to_form(changeset, as: :settings))

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.kasse
      flash={@flash}
      current_scope={@current_scope}
      areas={@areas}
      area={@area}
      account_groups={@account_groups}
      account_dialog={@account_dialog}
      current={:settings}
    >
      <.header>
        Gruppe
        <:subtitle>Name, Personen, Kategorien und mehr.</:subtitle>
      </.header>

      <div class="flex flex-col gap-8">
        <section aria-labelledby="settings-group">
          <.section_heading id="settings-group">Name</.section_heading>
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
        </section>

        <nav aria-label="Weitere Einstellungen">
          <.list id="settings-links">
            <.list_row
              :for={{key, label, plush, path} <- @links}
              id={"settings-link-#{key}"}
              title={label}
              navigate={path}
            >
              <:leading><.plush name={plush} size={:lg} /></:leading>
            </.list_row>
          </.list>
        </nav>
      </div>
    </Layouts.kasse>
    """
  end
end
