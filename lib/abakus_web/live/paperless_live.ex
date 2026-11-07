defmodule AbakusWeb.PaperlessLive do
  @moduledoc """
  Paperless in the settings: the URL and API token of the user's Paperless-ngx (ADR 0016), which the Depot takes
  receipts from and the Buchhaltung keeps attachments in.
  """
  use AbakusWeb, :live_view

  alias Abakus.Depot.{Receipts, Settings}
  alias Abakus.Depot.Receipts.PaperlessJob
  alias Abakus.Paperless

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.settings
      current={:paperless}
      flash={@flash}
      current_scope={@current_scope}
      areas={@areas}
      area={@area}
      groups={@settings_groups}
    >
      <.header>Paperless</.header>
      <section id="paperless">
        <p class="mb-3 flex flex-wrap items-center gap-x-2 font-medium">
          Paperless-ngx<span class="sr-only">:</span>
          <.badge
            id="paperless-status"
            tone={if Paperless.connected?(@connection), do: :success, else: :warning}
          >
            {if Paperless.connected?(@connection), do: "Verbunden", else: "Nicht verbunden"}
          </.badge>
        </p>
        <p class="mb-4 max-w-prose text-sm text-base-content/70">
          Dein eigenes Paperless-ngx: Das Depot holt seine Belege daraus, die Buchhaltung legt ihre Belege dort ab.
        </p>
        <.form for={@form} id="paperless-form" phx-submit="save">
          <.input
            field={@form[:url]}
            type="url"
            label="URL"
            placeholder="https://paperless.example.org"
            autocomplete="off"
            spellcheck="false"
          />
          <.input
            field={@form[:token]}
            type="password"
            label="API-Token"
            value=""
            autocomplete="off"
            placeholder={if @connection.token, do: "gespeichert"}
            help={
              if @connection.token,
                do:
                  "Leer lassen, um den gespeicherten Token zu behalten; eine neue URL braucht einen neuen.",
                else: "In Paperless unter „Mein Profil“."
            }
          />
          <.action_bar class="mt-4">
            <:secondary :if={Paperless.connected?(@connection)}>
              <.button
                id="paperless-disconnect"
                variant={:danger_outline}
                confirm="Paperless trennen?"
                confirm_text="URL und Token werden gelöscht."
                confirm_label="Trennen"
                phx-click="disconnect"
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

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Paperless")
     |> assign_connection(Paperless.get_connection(socket.assigns.current_scope))}
  end

  defp assign_connection(socket, connection) do
    assign(socket,
      connection: connection,
      form: to_form(Paperless.change_connection(connection), as: :paperless)
    )
  end

  @impl true
  def handle_event("save", %{"paperless" => params}, socket) do
    scope = socket.assigns.current_scope

    case Paperless.update_connection(scope, params) do
      {:ok, connection} ->
        if Receipts.paperless_intake?(scope),
          do: PaperlessJob.poll_soon(Settings.get_settings(scope))

        {:noreply, socket |> push_saved("paperless-save") |> assign_connection(connection)}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, as: :paperless, action: :update))}
    end
  end

  def handle_event("disconnect", _params, socket) do
    {:ok, connection} = Paperless.disconnect(socket.assigns.current_scope)
    {:noreply, socket |> put_flash(:info, "Paperless getrennt.") |> assign_connection(connection)}
  end
end
