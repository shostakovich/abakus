defmodule AbakusWeb.Depot.ReceiptIntakeLive do
  @moduledoc """
  „Belegeingang“ in the settings, for users with a portfolio: the tag of the documents in the user's Paperless-ngx
  that land in the inbox every 15 minutes (ADR 0016), and whether a model recognises receipts (ADR 0015).
  """
  use AbakusWeb, :depot_live_view

  alias Abakus.Depot.{Receipts, Settings}
  alias Abakus.Depot.Receipts.PaperlessJob
  alias Abakus.Depot.Settings.Setting
  alias Abakus.{Format, Paperless}
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
          Die Verbindung steht unter <.link
            id="paperless-link"
            navigate={~p"/settings/paperless"}
            class="link"
          >Paperless</.link>.
        </p>
        <ul class="mb-4 flex flex-col gap-3">
          <.intake_row
            id="paperless-status"
            title="Paperless-ngx"
            status={paperless_badge(@connected, @settings)}
            tone={paperless_tone(@connected, @settings)}
            detail={paperless_status(@connected, @settings, @polled_at)}
          />
          <.intake_row
            id="recognition-status"
            title="Belegerkennung"
            status={if @model_name, do: "Eingerichtet", else: "Kein Modell"}
            tone={if @model_name, do: :success, else: :neutral}
            detail={recognition_status(@model_name)}
          />
        </ul>
        <.form for={@tag_form} id="paperless-tag-form" phx-submit="save_tag">
          <.input
            field={@tag_form[:paperless_tag]}
            label="Tag"
            placeholder="abakus"
            autocomplete="off"
            spellcheck="false"
            help="Leer lassen, um keine Belege aus Paperless zu holen."
          />
          <.action_bar class="mt-4">
            <.button
              id="paperless-tag-save"
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

  defp paperless_badge(false, _settings), do: "Nicht verbunden"
  defp paperless_badge(true, %Setting{paperless_tag: nil}), do: "Kein Tag"
  defp paperless_badge(true, _settings), do: "Verbunden"

  defp paperless_tone(true, %Setting{paperless_tag: tag}) when tag != nil, do: :success
  defp paperless_tone(_connected, _settings), do: :warning

  defp paperless_status(true, %Setting{paperless_tag: tag}, polled_at) when tag != nil do
    polled =
      if polled_at,
        do: "zuletzt abgefragt #{Format.recent(polled_at)}",
        else: "noch nicht abgefragt"

    ["Tag „#{tag}“,", "danach „#{Receipts.done_tag(tag)}“ ·", polled]
  end

  defp paperless_status(_connected, _settings, _polled_at), do: []

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
     |> assign(:connected, Paperless.connected?(Paperless.get_connection(scope)))
     |> assign_settings(Settings.get_settings(scope))}
  end

  defp assign_settings(socket, settings) do
    assign(socket,
      settings: settings,
      polled_at: Receipts.paperless_polled_at(socket.assigns.current_scope),
      tag_form: to_form(Settings.change_paperless_tag(settings), as: :paperless)
    )
  end

  @impl true
  def handle_event("save_tag", %{"paperless" => params}, socket) do
    scope = socket.assigns.current_scope

    case Settings.update_paperless_tag(scope, params) do
      {:ok, settings} ->
        if Receipts.paperless_intake?(scope), do: PaperlessJob.poll_soon(settings)
        {:noreply, socket |> push_saved("paperless-tag-save") |> assign_settings(settings)}

      {:error, changeset} ->
        {:noreply, assign(socket, :tag_form, to_form(changeset, as: :paperless, action: :update))}
    end
  end
end
