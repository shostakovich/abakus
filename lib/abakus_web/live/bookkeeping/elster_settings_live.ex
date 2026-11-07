defmodule AbakusWeb.Bookkeeping.ElsterSettingsLive do
  @moduledoc """
  „ELSTER“ in the settings, for a user with the Buchhaltung: what sending a return needs (`Abakus.Bookkeeping.Filings`),
  the state of the tax office, which ELSTER takes with the tax number of „Rechnungen“, and the ELSTER certificate, a
  .pfx file. Its PIN is asked at every send.
  """
  use AbakusWeb, :live_view

  alias Abakus.Bookkeeping.{Filings, Invoices, States}
  alias AbakusWeb.{Areas, NotFoundError}

  @max_file_size 100_000

  @upload_errors %{
    too_large: "Die Datei ist größer als 100 KB.",
    too_many_files: "Bitte nur eine Datei wählen.",
    not_accepted: "Die Datei ist kein ELSTER-Zertifikat (.pfx)."
  }

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.settings
      current={:elster_settings}
      flash={@flash}
      current_scope={@current_scope}
      areas={@areas}
      area={@area}
      groups={@settings_groups}
    >
      <.header>
        ELSTER
        <:subtitle>Womit Abakus die Voranmeldungen an das Finanzamt sendet.</:subtitle>
      </.header>
      <p class="mb-4 flex flex-wrap items-center gap-x-2 font-medium">
        Senden<span class="sr-only">:</span>
        <.badge id="elster-status" tone={if @missing == [], do: :success, else: :warning}>
          {if @missing == [], do: "Bereit", else: "Es fehlt: #{Enum.join(@missing, ", ")}"}
        </.badge>
      </p>
      <.form for={@form} id="elster-settings-form" phx-submit="save">
        <p id="elster-tax-number" class="mb-2 text-sm">
          Steuernummer: {@settings.tax_number || "keine"} ·
          <.link navigate={~p"/settings/buchhaltung/invoices"} class="link">in „Rechnungen“ ändern</.link>
        </p>
        <.input
          field={@form[:tax_state]}
          type="select"
          label="Bundesland des Finanzamts"
          options={States.options()}
          prompt="Bitte wählen"
          class="max-w-80"
        />
        <.action_bar class="mt-4">
          <.button
            id="elster-settings-save"
            type="submit"
            variant={:primary}
            saved
            phx-disable-with="Speichert …"
          >
            Speichern
          </.button>
        </.action_bar>
      </.form>
      <section id="elster-certificate" class="mt-8">
        <h2 class="mb-2 font-medium">Zertifikat</h2>
        <p class="mb-3 max-w-prose text-sm text-base-content/70">
          Die Zertifikatsdatei aus „Mein ELSTER“. Ihre PIN fragt Abakus bei jedem Senden und speichert sie nie.
        </p>
        <div
          :if={@settings.elster_certificate_name}
          id="elster-certificate-stored"
          class="mb-3 flex flex-wrap items-center gap-3"
        >
          <.icon name="file-key" class="size-5 text-base-content/70" />
          <span>{@settings.elster_certificate_name}</span>
          <.button
            id="elster-certificate-remove"
            size={:sm}
            variant={:danger_outline}
            confirm="Zertifikat entfernen?"
            confirm_text="Ohne Zertifikat lässt sich nichts an ELSTER senden."
            confirm_label="Entfernen"
            phx-click="remove_certificate"
          >
            Entfernen
          </.button>
        </div>
        <form
          id="elster-certificate-form"
          phx-change="validate_certificate"
          phx-submit="validate_certificate"
        >
          <.file_drop
            upload={@uploads.certificate}
            label={
              if @settings.elster_certificate_name,
                do: "Anderes Zertifikat",
                else: "Zertifikat (.pfx)"
            }
            error_labels={@upload_errors}
            errors={@certificate_errors}
          />
        </form>
      </section>
    </Layouts.settings>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope
    Areas.allowed?(scope, :bookkeeping) || raise NotFoundError

    {:ok,
     socket
     |> assign(page_title: "ELSTER", upload_errors: @upload_errors, certificate_errors: nil)
     |> assign_settings(Invoices.get_settings(scope))
     |> allow_upload(:certificate,
       accept: ~w(.pfx .p12),
       max_entries: 1,
       max_file_size: @max_file_size,
       auto_upload: true,
       progress: &handle_progress/3
     )}
  end

  defp assign_settings(socket, settings) do
    assign(socket,
      settings: settings,
      form: to_form(Invoices.change_settings(settings)),
      missing: Filings.missing(socket.assigns.current_scope)
    )
  end

  defp handle_progress(:certificate, %{done?: true} = entry, socket) do
    content =
      consume_uploaded_entry(socket, entry, fn %{path: path} -> {:ok, File.read!(path)} end)

    case Filings.put_certificate(socket.assigns.current_scope, {content, entry.client_name}) do
      {:ok, settings} ->
        {:noreply,
         socket
         |> assign(certificate_errors: nil)
         |> assign_settings(settings)
         |> put_flash(:info, "Zertifikat gespeichert.")}

      {:error, changeset} ->
        {:noreply,
         assign(socket,
           certificate_errors: Keyword.get_values(changeset.errors, :elster_certificate)
         )}
    end
  end

  defp handle_progress(:certificate, _entry, socket), do: {:noreply, socket}

  @impl true
  def handle_event("validate_certificate", _params, socket), do: {:noreply, socket}

  def handle_event("save", %{"settings" => params}, socket) do
    case Invoices.save_settings(socket.assigns.current_scope, Map.take(params, ["tax_state"])) do
      {:ok, settings} ->
        {:noreply, socket |> assign_settings(settings) |> push_saved("elster-settings-save")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  def handle_event("remove_certificate", _params, socket) do
    {:ok, settings} = Filings.remove_certificate(socket.assigns.current_scope)
    {:noreply, socket |> assign_settings(settings) |> put_flash(:info, "Zertifikat entfernt.")}
  end
end
