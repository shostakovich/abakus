defmodule AbakusWeb.LexofficeImportLive do
  @moduledoc """
  Import & Sync's Lexoffice, for the budget owner with the Buchhaltung: the one-off import of the customers and
  invoices from Lexoffice (`Abakus.Bookkeeping.LexofficeImport`) with an API key that is entered for the run and
  not stored. It runs while the page is open, showing how far it is; run again, it brings only what is new.
  """
  use AbakusWeb, :live_view

  alias Abakus.Bookkeeping.LexofficeImport
  alias Abakus.{Format, Paperless}
  alias AbakusWeb.{Areas, ImportSync, NotFoundError}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      areas={@areas}
      area={@area}
      current={:import}
      account_groups={@account_groups}
      depot_sidebar={@depot_sidebar}
      expiring_consents={@expiring_consents}
      account_dialog={@account_dialog}
    >
      <ImportSync.import_header
        tab={:lexoffice}
        current_scope={@current_scope}
        inbox={@depot_sidebar.inbox}
      >
        <:subtitle>
          Kunden und Rechnungen aus Lexoffice, mit den Original-PDFs in Paperless.
        </:subtitle>
      </ImportSync.import_header>
      <div class="flex max-w-prose flex-col gap-6">
        <.alert :if={!@paperless?} id="lexoffice-no-paperless" tone={:warning}>
          Die PDFs der Rechnungen gehen nach Paperless. Bitte erst <.link
            navigate={~p"/settings/paperless"}
            class="link"
          >Paperless verbinden</.link>.
        </.alert>
        <.form for={@form} id="lexoffice-form" phx-submit="import">
          <p class="pb-4 text-sm text-base-content/70">
            Abakus übernimmt alle Kunden und geschriebenen Rechnungen, ob bezahlt, offen oder storniert. Ein
            zweiter Lauf bringt nur, was neu ist.
          </p>
          <.input
            field={@form[:token]}
            type="password"
            label="API-Schlüssel"
            value=""
            autocomplete="off"
            disabled={@running}
            help="In Lexoffice unter „Erweiterungen“ → „Public API“. Abakus speichert ihn nicht."
          />
          <.action_bar class="mt-4">
            <.button
              id="lexoffice-submit"
              type="submit"
              variant={:primary}
              icon="download"
              loading={@running}
              disabled={!@paperless?}
            >
              Importieren
            </.button>
          </.action_bar>
        </.form>
        <.alert :if={@running} id="lexoffice-progress" busy title="Import läuft">
          {progress_text(@progress)} Bitte die Seite offen lassen; ein abgebrochener Import macht beim
          nächsten Mal weiter.
        </.alert>
        <.alert :if={@error} id="lexoffice-error" tone={:error} title="Import abgebrochen">
          {@error}
        </.alert>
        <.alert
          :if={@result}
          id="lexoffice-result"
          tone={if @result.skipped == [], do: :success, else: :warning}
          title="Import fertig"
        >
          {result_text(@result)}
          <ul :if={@result.skipped != []} id="lexoffice-skipped" class="mt-2 list-disc ps-5">
            <li :for={{number, reason} <- @result.skipped}>{skipped_text(number, reason)}</li>
          </ul>
        </.alert>
      </div>
    </Layouts.app>
    """
  end

  defp progress_text(nil), do: "Kunden werden übernommen."

  defp progress_text({:customers, count}),
    do: "#{customers_text(count)} übernommen, die Rechnungen kommen."

  defp progress_text({:invoices, done, total}),
    do: "Rechnung #{Format.number(done)} von #{Format.number(total)}."

  defp result_text(%{customers: customers, invoices: invoices}),
    do: "#{customers_text(customers)} und #{invoices_text(invoices)} übernommen."

  defp customers_text(1), do: "1 Kunde"
  defp customers_text(count), do: "#{Format.number(count)} Kunden"

  defp invoices_text(1), do: "1 Rechnung"
  defp invoices_text(count), do: "#{Format.number(count)} Rechnungen"

  defp skipped_text(nil, reason), do: "Nicht übernommen: #{reason}"
  defp skipped_text(number, reason), do: "#{number} nicht übernommen: #{reason}"

  defp error_text(:not_connected), do: "Paperless ist nicht verbunden."
  defp error_text(:unauthorized), do: "Lexoffice nimmt den API-Schlüssel nicht an."
  defp error_text(:rate_limited), do: "Lexoffice bremst gerade. Bitte später noch einmal."

  defp error_text(:consuming),
    do: "Paperless braucht zu lange für ein PDF. Bitte noch einmal starten."

  defp error_text(reason) when reason in [:timeout, :unreachable],
    do: "Lexoffice oder Paperless ist nicht erreichbar."

  defp error_text(_reason), do: "Lexoffice oder Paperless hat einen Fehler gemeldet."

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope
    Areas.allowed?(scope, :bookkeeping) || raise NotFoundError

    {:ok,
     assign(socket,
       page_title: "Import & Sync",
       form: to_form(%{}, as: :lexoffice),
       paperless?: Paperless.connected?(Paperless.get_connection(scope)),
       running: false,
       progress: nil,
       result: nil,
       error: nil
     )}
  end

  @impl true
  def handle_event(
        "import",
        %{"lexoffice" => %{"token" => token}},
        %{assigns: %{running: false}} = socket
      ) do
    case String.trim(token) do
      "" ->
        {:noreply, assign(socket, error: "Bitte den API-Schlüssel eingeben.", result: nil)}

      token ->
        scope = socket.assigns.current_scope
        view = self()
        progress = &send(view, {:lexoffice_progress, &1})

        {:noreply,
         socket
         |> assign(running: true, progress: nil, result: nil, error: nil)
         |> start_async(:import, fn -> LexofficeImport.run(scope, fn -> token end, progress) end)}
    end
  end

  def handle_event("import", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_info({:lexoffice_progress, progress}, socket),
    do: {:noreply, assign(socket, :progress, progress)}

  @impl true
  def handle_async(:import, {:ok, {:ok, result}}, socket),
    do: {:noreply, assign(socket, running: false, result: result)}

  def handle_async(:import, {:ok, {:error, reason}}, socket),
    do: {:noreply, assign(socket, running: false, error: error_text(reason))}

  def handle_async(:import, {:exit, _reason}, socket),
    do: {:noreply, assign(socket, running: false, error: error_text(:crashed))}
end
