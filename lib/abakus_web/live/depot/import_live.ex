defmodule AbakusWeb.Depot.ImportLive do
  @moduledoc """
  Import & Sync's Portfolio Performance: imports a PP file, again and again, see `Abakus.Depot.PPImport`. Open
  before the first portfolio: a first import with a portfolio opens Finanzen, one that leaves no portfolio closes
  the Depot.
  """
  use AbakusWeb, :depot_live_view

  alias Abakus.Depot.{MarketData, Portfolios, PPImport}
  alias AbakusWeb.{Areas, ImportSync}

  @labels [
    securities: "Wertpapiere",
    prices: "Kurse",
    attribute_types: "Attribute",
    accounts: "Konten",
    portfolios: "Depots",
    transactions: "Buchungen",
    savings_plans: "Sparpläne",
    taxonomies: "Klassifizierungen",
    classifications: "Kategorien",
    assignments: "Zuordnungen"
  ]

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      areas={@areas}
      area={@area}
      current={:import_pp}
      account_groups={@account_groups}
      depot_sidebar={@depot_sidebar}
      account_dialog={@account_dialog}
    >
      <ImportSync.import_header tab={:pp} current_scope={@current_scope} inbox={@depot_sidebar.inbox} />
      <div class="flex flex-col gap-8">
        <section aria-labelledby="import-file-title">
          <.section_heading id="import-file-title">Datei importieren</.section_heading>
          <p class="mb-4 max-w-prose text-sm">
            Übernimmt Wertpapiere, Kurse, Depots, Konten, Buchungen, Sparpläne und Klassifizierungen.
            Ein erneuter Import gleicht alles an die Datei an; was du in Abakus eingestellt
            hast, etwa die Kursquelle, bleibt.
          </p>
          <.alert :if={@own_transactions?} tone={:warning} class="mb-4">
            Du hast schon Buchungen in Abakus erfasst. Sie bleiben erhalten; stehen sie auch
            in Portfolio Performance, sind sie danach doppelt.
          </.alert>
          <form id="import-form" phx-submit="import" phx-change="validate">
            <fieldset class="fieldset min-w-0">
              <label class="fieldset-legend" for={@uploads.pp_file.ref}>PP-Datei</label>
              <.live_file_input
                upload={@uploads.pp_file}
                class={[
                  "file-input w-full",
                  file_errors(@uploads.pp_file) != [] && "file-input-error"
                ]}
                aria-invalid={file_errors(@uploads.pp_file) != [] && "true"}
                aria-describedby={
                  field_describedby(@uploads.pp_file.ref, file_errors(@uploads.pp_file), true)
                }
              />
              <.field_error id={@uploads.pp_file.ref} errors={file_errors(@uploads.pp_file)} />
              <.field_help id={@uploads.pp_file.ref}>
                Die Datei .portfolio im Binärformat, unverschlüsselt.
              </.field_help>
            </fieldset>
            <.action_bar class="mt-4">
              <.button
                type="submit"
                variant={:primary}
                phx-disable-with="Wird importiert …"
                disabled={@uploads.pp_file.entries == []}
              >
                Importieren
              </.button>
            </.action_bar>
          </form>
        </section>

        <section :if={@summary} id="import-summary" aria-labelledby="import-summary-title">
          <.section_heading id="import-summary-title">Ergebnis</.section_heading>
          <.table
            id="import-summary-rows"
            rows={labels()}
            row_id={fn {kind, _label} -> "summary-#{kind}" end}
            size={:sm}
          >
            <:col :let={{_kind, label}} label="Bereich">{label}</:col>
            <:col :let={{kind, _label}} label="neu" align={:end}>{@summary[kind].created}</:col>
            <:col :let={{kind, _label}} label="geändert" align={:end}>
              {@summary[kind].updated}
            </:col>
            <:col :let={{kind, _label}} label="gelöscht" align={:end}>
              {@summary[kind].deleted}
            </:col>
          </.table>
        </section>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Portfolio Performance")
     |> assign(:summary, nil)
     |> assign(:own_transactions?, Portfolios.own_transactions?(socket.assigns.current_scope))
     # `.portfolio` has no MIME type; the reader checks the contents instead.
     |> allow_upload(:pp_file, accept: :any, max_entries: 1, max_file_size: 100_000_000)}
  end

  @impl true
  def handle_event("validate", _params, socket), do: {:noreply, socket}

  def handle_event("import", _params, socket) do
    case uploaded_entries(socket, :pp_file) do
      {[_entry], []} -> import_file(socket)
      _not_ready -> {:noreply, socket}
    end
  end

  defp import_file(socket) do
    scope = socket.assigns.current_scope

    [result] =
      consume_uploaded_entries(socket, :pp_file, fn %{path: path}, _entry ->
        {:ok, PPImport.run(scope, path)}
      end)

    case result do
      {:ok, summary} ->
        MarketData.broadcast()

        {:noreply,
         socket
         |> assign(:summary, summary)
         |> put_flash(:info, "Import abgeschlossen.")
         |> put_depot()}

      {:error, reason} ->
        {:noreply, socket |> assign(:summary, nil) |> put_flash(:error, error_message(reason))}
    end
  end

  defp put_depot(socket) do
    if Portfolios.any?(socket.assigns.current_scope.user),
      do: Areas.open_depot(socket),
      else: Areas.close_depot(socket)
  end

  defp labels, do: @labels

  defp file_errors(upload) do
    (upload_errors(upload) ++ Enum.flat_map(upload.entries, &upload_errors(upload, &1)))
    |> Enum.map(&upload_error/1)
  end

  defp upload_error(:too_large), do: "Die Datei ist zu groß."
  defp upload_error(:too_many_files), do: "Bitte nur eine Datei wählen."
  defp upload_error(_), do: "Die Datei ließ sich nicht hochladen."

  defp error_message(:xml_format),
    do: "Die Datei ist im XML-Format. Speichere sie in Portfolio Performance als Binärdatei."

  defp error_message(:too_large), do: "Die Datei ist entpackt zu groß."

  defp error_message(message) when is_binary(message), do: message

  defp error_message(:malformed), do: "Die Datei ist beschädigt oder hat ein unbekanntes Format."

  defp error_message(_),
    do: "Das ist keine (unverschlüsselte) Datei aus Portfolio Performance."
end
