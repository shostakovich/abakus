defmodule AbakusWeb.Depot.ReceiptsLive do
  @moduledoc """
  Import & Sync's Belege, for users with a portfolio: the inbox („Eingang“) with the receipts from Paperless and the
  uploaded ones, see `Abakus.Depot.Receipts`; „PDF hochladen“ takes one or several at once. A receipt opens the
  dialog „Beleg prüfen“.
  """
  use AbakusWeb, :depot_live_view

  alias Abakus.Depot.{Receipts, Securities}
  alias AbakusWeb.{Areas, ImportSync, NotFoundError}
  alias AbakusWeb.Depot.ReceiptComponents

  @max_uploads 10

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.depot
      flash={@flash}
      current_scope={@current_scope}
      sidebar={@depot_sidebar}
      expiring_consents={@expiring_consents}
      areas={@areas}
      area={@area}
      account_groups={@account_groups}
      account_dialog={@account_dialog}
      current={:receipts}
    >
      <ImportSync.import_header
        tab={:receipts}
        current_scope={@current_scope}
        inbox={@depot_sidebar.inbox}
      >
        <:subtitle>PDF-Belege deiner Bank, aus Paperless-ngx oder hochgeladen.</:subtitle>
        <:actions>
          <form id="receipts-upload" phx-change="upload" phx-submit="upload">
            <label class={[
              "btn has-focus-visible:outline-2 has-focus-visible:outline-offset-2",
              "has-focus-visible:outline-primary"
            ]}>
              <.icon name="upload" /> PDF hochladen
              <.live_file_input upload={@uploads.receipts} class="sr-only" />
            </label>
          </form>
        </:actions>
      </ImportSync.import_header>

      <div :if={receipt_upload_errors(@uploads) != []} class="mb-6 flex flex-col gap-2">
        <.alert :for={message <- receipt_upload_errors(@uploads)} tone={:error}>{message}</.alert>
      </div>

      <ReceiptComponents.inbox
        :if={@inbox != []}
        receipts={@inbox}
        names={@names}
        polled_at={@polled_at}
      />

      <.empty_state
        :if={@inbox == []}
        id="inbox-empty"
        layout={:page}
        plush="file-text"
        icon="file-text"
        title="Keine Belege im Eingang"
      >
        Lade den PDF-Beleg deiner Bank hoch, oder verbinde Paperless-ngx unter Einstellungen › Belegeingang.
      </.empty_state>
    </Layouts.depot>
    """
  end

  defp receipt_upload_errors(uploads) do
    upload = uploads.receipts
    entry_errors = Enum.flat_map(upload.entries, &upload_errors(upload, &1))
    (upload_errors(upload) ++ entry_errors) |> Enum.uniq() |> Enum.map(&upload_error/1)
  end

  defp upload_error(:too_large), do: "Eine Datei ist zu groß, höchstens 20 MB."
  defp upload_error(:not_accepted), do: "Bitte nur PDF-Dateien wählen."
  defp upload_error(:too_many_files), do: "Bitte höchstens #{@max_uploads} Dateien auf einmal."
  defp upload_error(_error), do: "Eine Datei ließ sich nicht hochladen."

  @impl true
  def mount(_params, _session, socket) do
    Areas.allowed?(socket.assigns.current_scope, :depot) || raise NotFoundError

    {:ok,
     socket
     |> assign(page_title: "Belege", uploaded: %{})
     |> load_inbox()
     |> allow_upload(:receipts,
       accept: ~w(.pdf),
       max_entries: @max_uploads,
       max_file_size: 20_000_000,
       auto_upload: true,
       progress: &uploaded/3
     )}
  end

  # Each PDF goes into the inbox once it is up; once all of them are, one flash sums them up.
  defp uploaded(:receipts, entry, socket) do
    if entry.done? do
      scope = socket.assigns.current_scope

      result =
        consume_uploaded_entry(socket, entry, fn %{path: path} ->
          {:ok, Receipts.upload(scope, path, entry.client_name)}
        end)

      socket = update(socket, :uploaded, &Map.put(&1, entry.ref, {result, entry.client_name}))
      {:noreply, socket |> maybe_upload_flash() |> load_inbox()}
    else
      {:noreply, socket}
    end
  end

  # Consumed entries leave the upload only after the callback.
  defp maybe_upload_flash(socket) do
    %{uploaded: uploaded, uploads: %{receipts: upload}} = socket.assigns

    if Enum.all?(upload.entries, &(Map.has_key?(uploaded, &1.ref) or not &1.valid?)) do
      results = Map.values(uploaded)

      kind =
        if Enum.any?(results, &match?({{:error, _reason}, _name}, &1)), do: :error, else: :info

      message =
        results
        |> Enum.group_by(fn {result, _name} -> result end, fn {_result, name} -> name end)
        |> Enum.sort()
        |> Enum.map_join(" ", fn {result, names} -> upload_message(result, names) end)

      socket |> assign(:uploaded, %{}) |> put_flash(kind, message)
    else
      socket
    end
  end

  defp upload_message({:ok, :added}, [name]), do: "#{name} liegt im Eingang."
  defp upload_message({:ok, :added}, names), do: "#{length(names)} Belege liegen im Eingang."
  defp upload_message({:ok, :in_inbox}, [name]), do: "#{name} liegt schon im Eingang."

  defp upload_message({:ok, :in_inbox}, names),
    do: "#{length(names)} Belege liegen schon im Eingang."

  defp upload_message({:ok, :booked}, [name]), do: "#{name} ist schon gebucht."
  defp upload_message({:ok, :booked}, names), do: "#{length(names)} Belege sind schon gebucht."
  defp upload_message({:error, :not_pdf}, [name]), do: "#{name} ist keine PDF-Datei."

  defp upload_message({:error, :not_pdf}, names),
    do: "#{length(names)} Dateien sind keine PDF-Dateien."

  @impl true
  # A rejected file is said once and dropped, so it neither sticks nor counts to the limit.
  def handle_event("upload", _params, socket) do
    upload = socket.assigns.uploads.receipts
    rejected = Enum.reject(upload.entries, & &1.valid?) ++ Enum.drop(upload.entries, @max_uploads)

    case receipt_upload_errors(socket.assigns.uploads) do
      [] ->
        {:noreply, socket}

      errors ->
        {:noreply,
         rejected
         |> Enum.uniq_by(& &1.ref)
         |> Enum.reduce(socket, &cancel_upload(&2, :receipts, &1.ref))
         |> put_flash(:error, Enum.join(errors, " "))}
    end
  end

  def handle_event("discard", %{"id" => id}, socket) do
    message =
      case Receipts.discard(socket.assigns.current_scope, id) do
        :ok -> "Beleg verworfen."
        {:error, :gone} -> "Dieser Beleg liegt nicht mehr im Eingang."
      end

    {:noreply, socket |> put_flash(:info, message) |> load_inbox()}
  end

  @impl true
  def handle_info(:market_data_updated, socket), do: {:noreply, load_inbox(socket)}
  def handle_info(:receipts_updated, socket), do: {:noreply, load_inbox(socket)}

  defp load_inbox(socket) do
    scope = socket.assigns.current_scope
    names = Map.new(Securities.list_securities(scope), &{&1.isin, &1.name})

    assign(socket,
      inbox: Receipts.list_inbox(scope),
      names: names,
      polled_at: Receipts.paperless_polled_at(scope)
    )
  end
end
