defmodule AbakusWeb.Depot.ReceiptIntakeLive do
  @moduledoc """
  „Belegeingang“ in the settings, for users with a portfolio: the user's Paperless-ngx, whose documents with their
  tag land in the inbox every 15 minutes (ADR 0016), and whether a model recognises receipts (ADR 0015).
  """
  use AbakusWeb, :depot_live_view

  alias Abakus.Depot.{Receipts, Settings}
  alias Abakus.Depot.Receipts.PaperlessJob
  alias Abakus.Depot.Settings.Setting
  alias Abakus.Format
  alias AbakusWeb.{Areas, NotFoundError}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.settings
      current={:receipt_intake}
      flash={@flash}
      current_scope={@current_scope}
      areas={@areas}
      area={@area}
      groups={@settings_groups}
    >
      <.header>Belegeingang</.header>
      <section id="receipt-intake">
        <p class="mb-3 max-w-prose text-sm text-base-content/70">
          Holt alle 15 Minuten die Dokumente mit deinem Tag aus Paperless-ngx in den Eingang unter Import &amp; Sync.
        </p>
        <ul class="mb-4 flex flex-col gap-3">
          <.intake_row
            id="paperless-status"
            title="Paperless-ngx"
            status={if Setting.paperless?(@settings), do: "Verbunden", else: "Nicht verbunden"}
            tone={if Setting.paperless?(@settings), do: :success, else: :warning}
            detail={paperless_status(@settings)}
          />
          <.intake_row
            id="recognition-status"
            title="Belegerkennung"
            status={if @model_name, do: "Eingerichtet", else: "Kein Modell"}
            tone={if @model_name, do: :success, else: :neutral}
            detail={recognition_status(@model_name)}
          />
        </ul>
        <.form for={@paperless_form} id="paperless-form" phx-submit="save_paperless">
          <.input
            field={@paperless_form[:paperless_url]}
            type="url"
            label="URL"
            placeholder="https://paperless.example.org"
            autocomplete="off"
            spellcheck="false"
          />
          <.input
            field={@paperless_form[:paperless_token]}
            type="password"
            label="API-Token"
            value=""
            autocomplete="off"
            placeholder={if @settings.paperless_token, do: "gespeichert"}
            help={
              if @settings.paperless_token,
                do:
                  "Leer lassen, um den gespeicherten Token zu behalten; eine neue URL braucht einen neuen.",
                else: "In Paperless unter „Mein Profil“."
            }
          />
          <.input
            field={@paperless_form[:paperless_tag]}
            label="Tag"
            placeholder="abakus"
            autocomplete="off"
            spellcheck="false"
          />
          <.action_bar class="mt-4">
            <:secondary :if={Setting.paperless?(@settings)}>
              <.button
                id="paperless-disconnect"
                variant={:danger_outline}
                confirm="Paperless trennen?"
                confirm_text="URL, Token und Tag werden gelöscht."
                confirm_label="Trennen"
                phx-click="disconnect_paperless"
              >
                Trennen
              </.button>
            </:secondary>
            <.button
              id="paperless-save"
              type="submit"
              variant={:primary}
              saved
              phx-disable-with="Speichert …"
            >
              Speichern
            </.button>
          </.action_bar>
        </.form>
      </section>
    </Layouts.settings>
    """
  end

  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :status, :string, required: true
  attr :tone, :atom, required: true
  attr :detail, :list, required: true, doc: "its parts, each with its punctuation; none wraps"

  defp intake_row(assigns) do
    ~H"""
    <li id={@id}>
      <p class="flex flex-wrap items-center gap-x-2 font-medium">
        {@title}<span class="sr-only">:</span>
        <.badge tone={@tone} data-status>{@status}</.badge>
      </p>
      <p :if={@detail != []} class="text-sm text-base-content/70" data-detail>
        <%= for part <- @detail do %>
          <span class="whitespace-nowrap" data-part>{part}</span>
        <% end %>
      </p>
    </li>
    """
  end

  defp paperless_status(settings) do
    if Setting.paperless?(settings) do
      tag = settings.paperless_tag

      polled =
        if settings.paperless_polled_at,
          do: "zuletzt abgefragt #{Format.recent(settings.paperless_polled_at)}",
          else: "noch nicht abgefragt"

      ["Tag „#{tag}“,", "danach „#{Receipts.done_tag(tag)}“ ·", polled]
    else
      []
    end
  end

  defp recognition_status(nil), do: ["Belege öffnen", "ein leeres Formular."]

  defp recognition_status(name),
    do: ["#{name} ·", "Text aus Paperless,", "sonst aus dem PDF"]

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope
    Areas.allowed?(scope, :depot) || raise NotFoundError

    {:ok,
     socket
     |> assign(:page_title, "Belegeingang")
     |> assign(:model_name, Receipts.model_name())
     |> assign_settings(Settings.get_settings(scope))}
  end

  defp assign_settings(socket, settings) do
    assign(socket,
      settings: settings,
      paperless_form: to_form(Settings.change_paperless(settings), as: :paperless)
    )
  end

  @impl true
  def handle_event("save_paperless", %{"paperless" => params}, socket) do
    case Settings.update_paperless(socket.assigns.current_scope, params) do
      {:ok, settings} ->
        PaperlessJob.poll_soon(settings)
        {:noreply, socket |> push_saved("paperless-save") |> assign_settings(settings)}

      {:error, changeset} ->
        {:noreply,
         assign(socket, :paperless_form, to_form(changeset, as: :paperless, action: :update))}
    end
  end

  def handle_event("disconnect_paperless", _params, socket) do
    {:ok, settings} = Settings.disconnect_paperless(socket.assigns.current_scope)
    {:noreply, socket |> put_flash(:info, "Paperless getrennt.") |> assign_settings(settings)}
  end
end
