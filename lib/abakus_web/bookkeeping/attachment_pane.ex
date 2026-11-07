defmodule AbakusWeb.Bookkeeping.AttachmentPane do
  @moduledoc """
  The attachments beside a transaction in the dialog „Buchhaltung“: those attached, the documents Paperless proposes
  (`Abakus.Bookkeeping.Attachments.proposals/2`), an upload to Paperless, and the document shown with its text and
  its PDF. For a split, „Für“ chooses whether an attachment is the whole transaction's or one part's. Paperless is read
  in the background, so the dialog opens at once; without a Paperless connection the pane points to the settings.
  """
  use AbakusWeb, :live_component

  alias Abakus.Bookkeeping.Attachments
  alias Abakus.{Format, Money, Paperless, Schema}
  alias AbakusWeb.Bookkeeping.TaxLineDialog

  @accept ~w(.pdf .jpg .jpeg .png .tif .tiff .webp)
  @max_file_size 20_000_000

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :shown_document, shown_document(assigns))

    ~H"""
    <section id={@id} class="flex min-w-0 flex-col gap-4" aria-labelledby={"#{@id}-heading"}>
      <h3 id={"#{@id}-heading"} class="text-sm font-medium">Belege</h3>
      <.alert :if={!@connected} id="attachments-not-connected" tone={:neutral}>
        Belege liegen in Paperless. Verbinde es unter <.link
          navigate={~p"/settings/paperless"}
          class="link"
        >Einstellungen › Paperless</.link>.
      </.alert>
      <form
        :if={@connected and length(@sides) > 1}
        id="attachments-side-form"
        phx-change="side"
        phx-target={@myself}
      >
        <.input
          id="attachments-side"
          type="select"
          name="side"
          value={@side}
          options={Enum.map(@sides, &{&1.label, &1.key})}
          label="Für"
        />
      </form>
      <.list :if={@attachments != []} id="attachments-attached" size={:compact}>
        <.list_row
          :for={attachment <- @attachments}
          id={"attachment-#{attachment.id}"}
          title={attachment.title}
          on_click={JS.push("show", value: %{id: attachment.paperless_id}, target: @myself)}
          selected={@shown == attachment.paperless_id}
        >
          <:leading><.icon name="paperclip" class="size-4 text-base-content/70" /></:leading>
          <:meta :if={attachment.subtransaction_id}>{side_label(@sides, attachment)}</:meta>
          <:action
            id={"attachment-#{attachment.id}-detach"}
            label="Lösen"
            icon="unlink"
            on_click={JS.push("detach", value: %{id: attachment.id}, target: @myself)}
          />
        </.list_row>
      </.list>
      <div :if={@connected} id="attachments-proposals" class="flex flex-col gap-1">
        <h4 class="text-sm text-base-content/70">Vorschläge aus Paperless</h4>
        <p :if={@proposals == nil} id="attachments-searching" class="text-sm text-base-content/70">
          Paperless wird durchsucht …
        </p>
        <p :if={@proposals == []} id="attachments-no-proposals" class="text-sm text-base-content/70">
          Kein Dokument mit diesem Betrag aus der Zeit der Buchung.
        </p>
        <.list :if={@proposals not in [nil, []]} id="attachments-proposed" size={:compact}>
          <.list_row
            :for={document <- @proposals}
            id={"proposal-#{document.id}"}
            title={title(document)}
            on_click={JS.push("show", value: %{id: document.id}, target: @myself)}
            selected={@shown == document.id}
          >
            <:meta :if={document.created}>{Format.date(document.created)}</:meta>
            <:action
              id={"proposal-#{document.id}-attach"}
              label="Anhängen"
              icon="paperclip"
              on_click={JS.push("attach", value: %{id: document.id}, target: @myself)}
            />
          </.list_row>
        </.list>
      </div>
      <form
        :if={@connected}
        id="attachments-upload"
        phx-change="validate"
        phx-submit="validate"
        phx-target={@myself}
      >
        <label class={[
          "btn btn-sm has-focus-visible:outline-2 has-focus-visible:outline-offset-2",
          "has-focus-visible:outline-primary",
          @uploading && "btn-disabled"
        ]}>
          <.icon name="upload" /> {if @uploading,
            do: "Wird an Paperless übergeben …",
            else: "Hochladen"}
          <.live_file_input upload={@uploads.attachment} class="sr-only" disabled={@uploading} />
        </label>
      </form>
      <.alert :if={errors(@error, @uploads) != []} id="attachments-error" tone={:error}>
        <p :for={message <- errors(@error, @uploads)}>{message}</p>
      </.alert>
      <.shown :if={@shown} id={@shown} document={@shown_document} />
    </section>
    """
  end

  attr :id, :integer, required: true
  attr :document, :map, required: true

  defp shown(assigns) do
    ~H"""
    <div id="attachment-shown" class="flex min-w-0 flex-col gap-2">
      <div class="flex min-h-8 items-center justify-between gap-2">
        <h4 class="min-w-0 truncate text-sm text-base-content/70">{title(@document)}</h4>
        <.button
          id="attachment-pdf"
          href={~p"/buchhaltung/paperless/#{@id}"}
          target="_blank"
          rel="noopener"
          variant={:ghost}
          size={:sm}
          icon="file-text"
        >
          PDF öffnen
        </.button>
      </div>
      <div
        :if={text(@document)}
        class="max-h-96 overflow-y-auto rounded-box border border-base-content/10 bg-base-100 p-4"
      >
        <pre
          id="attachment-text"
          class="app-receipt-lines"
          tabindex="0"
          aria-label="Text des Belegs"
        >{text(@document)}</pre>
      </div>
      <p :if={!text(@document)} id="attachment-text" class="text-sm text-base-content/70">
        Paperless hat zu diesem Dokument keinen Text.
      </p>
    </div>
    """
  end

  defp shown_document(%{shown: nil}), do: nil

  defp shown_document(assigns) do
    assigns.documents[assigns.shown] ||
      Enum.find_value(assigns.attachments, %{id: assigns.shown}, fn attachment ->
        attachment.paperless_id == assigns.shown && %{id: assigns.shown, title: attachment.title}
      end)
  end

  defp title(document),
    do:
      Enum.find([document[:title], document[:filename]], &(&1 not in [nil, ""])) ||
        "Paperless #{document.id}"

  defp text(document) do
    case document[:content] do
      text when is_binary(text) -> if String.trim(text) != "", do: text
      _none -> nil
    end
  end

  defp side_label(sides, attachment),
    do:
      Enum.find_value(sides, &(&1.part && &1.part.id == attachment.subtransaction_id && &1.label))

  defp errors(error, uploads) do
    upload_errors =
      Enum.map(
        upload_errors(uploads.attachment) ++
          Enum.flat_map(uploads.attachment.entries, &upload_errors(uploads.attachment, &1)),
        &upload_error/1
      )

    Enum.uniq(List.wrap(error) ++ upload_errors)
  end

  defp upload_error(:too_large), do: "Die Datei ist zu groß, höchstens 20 MB."
  defp upload_error(:not_accepted), do: "Bitte ein PDF oder ein Bild wählen."
  defp upload_error(_error), do: "Die Datei ließ sich nicht hochladen."

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> assign(transaction: nil, uploading: false)
     |> allow_upload(:attachment,
       accept: @accept,
       max_entries: 1,
       max_file_size: @max_file_size,
       auto_upload: true,
       progress: &uploaded/3
     )}
  end

  @impl true
  def update(%{transaction: transaction} = assigns, socket) do
    socket = assign(socket, id: assigns.id, current_scope: assigns.current_scope)

    if socket.assigns.transaction && socket.assigns.transaction.id == transaction.id,
      do: {:ok, assign(socket, :transaction, transaction)},
      else: {:ok, load(socket, transaction)}
  end

  defp load(socket, transaction) do
    scope = socket.assigns.current_scope
    attachments = attachments(scope, transaction)
    connected = Paperless.connected?(Paperless.get_connection(scope))

    socket =
      assign(socket,
        transaction: transaction,
        sides: sides(transaction),
        side: "transaction",
        attachments: attachments,
        connected: connected,
        uploading: false,
        documents: %{},
        proposals: nil,
        shown: attachments |> List.first() |> then(&(&1 && &1.paperless_id)),
        error: nil
      )

    if connected,
      do: start_async(socket, :read, fn -> read(scope, transaction, attachments) end),
      else: socket
  end

  defp sides(transaction) do
    parts = Map.new(transaction.subtransactions, &{&1.id, &1})

    for side <- Attachments.sides(transaction) do
      part = side && parts[side]

      label =
        if part,
          do:
            join_meta([
              TaxLineDialog.part_name(part, transaction),
              Money.euros(part.amount, signed: true)
            ]),
          else: "Ganze Buchung"

      %{key: side || "transaction", part: part, label: label}
    end
  end

  defp attachments(scope, transaction) do
    attached = Attachments.list(scope, [transaction])
    for side <- Attachments.sides(transaction), a <- attached[{transaction.id, side}] || [], do: a
  end

  defp read(scope, transaction, attachments) do
    documents =
      for id <- attachments |> Enum.map(& &1.paperless_id) |> Enum.uniq(),
          {:ok, document} <- [Attachments.document(scope, id)],
          into: %{},
          do: {id, document}

    {documents, Attachments.proposals(scope, transaction)}
  end

  @impl true
  def handle_async(:read, {:ok, {documents, {:ok, proposals}}}, socket) do
    documents = Map.merge(Map.new(proposals, &{&1.id, &1}), documents)
    shown = socket.assigns.shown || Enum.find_value(proposals, & &1.id)
    {:noreply, assign(socket, documents: documents, proposals: proposals, shown: shown)}
  end

  def handle_async(:read, {:ok, {documents, {:error, reason}}}, socket),
    do: {:noreply, assign(socket, documents: documents, proposals: [], error: message(reason))}

  def handle_async(:read, {:exit, _reason}, socket),
    do: {:noreply, assign(socket, proposals: [], error: message(:unreachable))}

  def handle_async(
        :upload,
        {:ok, {id, _result}},
        %{assigns: %{transaction: %{id: shown}}} = socket
      )
      when id != shown,
      do: {:noreply, socket}

  def handle_async(:upload, {:ok, {_id, {:ok, attachment, document}}}, socket) do
    socket = socket |> assign(uploading: false, error: nil) |> attached(attachment)

    case document do
      {:ok, document} ->
        {:noreply, update(socket, :documents, &Map.put(&1, document.id, document))}

      _unread ->
        {:noreply, socket}
    end
  end

  def handle_async(:upload, {:ok, {_id, {:error, reason}}}, socket),
    do: {:noreply, assign(socket, uploading: false, error: message(reason))}

  def handle_async(:upload, {:exit, _reason}, %{assigns: %{uploading: false}} = socket),
    do: {:noreply, socket}

  def handle_async(:upload, {:exit, _reason}, socket),
    do: {:noreply, assign(socket, uploading: false, error: message(:unreachable))}

  @impl true
  def handle_event("show", %{"id" => id}, socket) do
    case Schema.cast_id(id) do
      {:ok, id} -> {:noreply, assign(socket, :shown, id)}
      :error -> {:noreply, socket}
    end
  end

  def handle_event("side", %{"side" => side}, socket) do
    side = if Enum.any?(socket.assigns.sides, &(&1.key == side)), do: side, else: "transaction"
    {:noreply, assign(socket, :side, side)}
  end

  def handle_event("attach", %{"id" => id}, socket) do
    %{current_scope: scope, transaction: transaction} = socket.assigns

    with {:ok, id} <- Schema.cast_id(id),
         {:ok, attachment} <- Attachments.attach(scope, transaction, side(socket), id) do
      {:noreply, socket |> assign(:error, nil) |> attached(attachment)}
    else
      :error -> {:noreply, socket}
      {:error, reason} -> {:noreply, assign(socket, :error, message(reason))}
    end
  end

  def handle_event("detach", %{"id" => id}, socket) do
    %{current_scope: scope, transaction: transaction} = socket.assigns
    :ok = Attachments.detach(scope, id)
    {:noreply, assign(socket, :attachments, attachments(scope, transaction))}
  end

  def handle_event("validate", _params, socket), do: {:noreply, socket}

  defp uploaded(:attachment, %{done?: true} = entry, socket) do
    %{current_scope: scope, transaction: transaction} = socket.assigns
    side = side(socket)

    content =
      consume_uploaded_entry(socket, entry, fn %{path: path} -> {:ok, File.read!(path)} end)

    socket =
      socket
      |> assign(uploading: true, error: nil)
      |> start_async(:upload, fn ->
        result =
          with {:ok, attachment} <-
                 Attachments.upload(scope, transaction, side, content, entry.client_name) do
            {:ok, attachment, Attachments.document(scope, attachment.paperless_id)}
          end

        {transaction.id, result}
      end)

    {:noreply, socket}
  end

  defp uploaded(:attachment, _entry, socket), do: {:noreply, socket}

  defp attached(socket, attachment) do
    %{current_scope: scope, transaction: transaction} = socket.assigns

    assign(socket,
      attachments: attachments(scope, transaction),
      proposals:
        socket.assigns.proposals &&
          Enum.reject(socket.assigns.proposals, &(&1.id == attachment.paperless_id)),
      shown: attachment.paperless_id
    )
  end

  defp side(%{assigns: %{side: "transaction"}}), do: nil
  defp side(%{assigns: %{side: side}}), do: side

  defp message(:not_connected), do: "Paperless ist nicht verbunden."
  defp message(:not_found), do: "Diese Buchung gibt es nicht mehr."
  defp message(:side), do: "Diesen Teil der Buchung gibt es nicht mehr."

  defp message(:consuming),
    do:
      "Paperless braucht für die Datei länger. Lade sie später noch einmal hoch, dann wird sie angehängt."

  defp message(:not_consumed), do: "Paperless hat die Datei nicht angenommen."

  defp message({:http_status, status}) when status in [401, 403],
    do: "Paperless hat den API-Token abgelehnt. Prüfe ihn unter Einstellungen › Paperless."

  defp message({:http_status, 413}), do: "Die Datei ist zu groß für Paperless."
  defp message(_unreachable), do: "Paperless ist gerade nicht erreichbar."
end
