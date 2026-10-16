defmodule AbakusWeb.ImportLive do
  @moduledoc """
  Import & Sync's Bankdateien, the file import: a chosen OFX/QFX file is read at once and previewed per statement, with
  the file's account, the bank balance it reports, the account it goes into and its transactions: new, there
  already, a match proposal for a transaction in the register, or before the last reconcile (skipped). A file
  account seen before has its linked account chosen; an unknown one asks for the account. The import remembers the
  chosen one, so choosing another moves the link. Accounts fed by another app and closed ones are not offered. The
  preview lives in the LiveView only; the import checks again what is there.
  """
  use AbakusWeb, :live_view

  alias Abakus.{FileImport, Format, Ledger}
  alias AbakusWeb.ImportSync
  alias AbakusWeb.RegisterLive.{Components, TransactionEditor}

  @max_file_size 5_000_000

  @upload_errors %{
    too_large: "Die Datei ist größer als 5 MB.",
    too_many_files: "Bitte nur eine Datei wählen.",
    not_accepted: "Die Datei ist keine OFX- oder QFX-Datei."
  }

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
      account_dialog={@account_dialog}
    >
      <ImportSync.import_header
        tab={:files}
        current_scope={@current_scope}
        inbox={@depot_sidebar.inbox}
      >
        <:subtitle>
          Umsätze aus dem Bank-Export (OFX oder QFX). Konten, die eine andere App füllt, nehmen keinen
          Datei-Import.
        </:subtitle>
      </ImportSync.import_header>
      <div class="flex flex-col gap-6">
        <form id="import-form" phx-change="validate" phx-submit="validate">
          <p id="import-steps" class="max-w-prose pb-2 text-sm text-base-content/70">
            In der Banking-App die Umsätze des Kontos als OFX oder QFX exportieren und die Datei hier ablegen.
            Buchungen, die schon da sind, erkennt Abakus an der FITID der Bank.
          </p>
          <.file_drop
            upload={@uploads.file}
            label="OFX- oder QFX-Datei"
            error_labels={upload_errors()}
          />
        </form>
        <.preview
          :if={@preview}
          preview={@preview}
          accounts={@accounts}
          transfer_accounts={@transfer_accounts}
        />
      </div>
    </Layouts.app>
    """
  end

  attr :preview, :map, required: true
  attr :accounts, :list, required: true
  attr :transfer_accounts, :map, required: true

  defp preview(assigns) do
    assigns =
      assign(assigns,
        transactions: Enum.flat_map(assigns.preview.statements, & &1.statement.transactions),
        incoming:
          assigns.preview.statements
          |> Enum.map(&(&1.preview.new + &1.preview.matched))
          |> Enum.sum(),
        ready: Enum.all?(assigns.preview.statements, & &1.account)
      )

    ~H"""
    <.card
      id="import-preview"
      bleed={:phone}
      title={@preview.file_name}
      subtitle={join_meta([transactions_text(length(@transactions)), period(@transactions)])}
    >
      <:leading><.icon name="file-text" class="size-5 text-base-content/70" /></:leading>
      <:list>
        <.statement
          :for={{item, index} <- Enum.with_index(@preview.statements)}
          item={item}
          index={index}
          accounts={@accounts}
          transfer_accounts={@transfer_accounts}
        />
        <div class="px-6 pt-4 pb-6">
          <p class="max-w-prose text-sm text-base-content/70">
            Neue Buchungen landen unbestätigt im Konto, Zuordnungsvorschläge warten auf Zuordnen oder
            Trennen.
          </p>
          <.action_bar class="mt-4">
            <.button id="import-discard" phx-click="discard">Verwerfen</.button>
            <.button id="import-submit" variant={:primary} phx-click="import" disabled={!@ready}>
              {import_label(@incoming)}
            </.button>
          </.action_bar>
        </div>
      </:list>
    </.card>
    """
  end

  attr :item, :map, required: true
  attr :index, :integer, required: true
  attr :accounts, :list, required: true
  attr :transfer_accounts, :map, required: true, doc: "every account by id, naming transfers"

  defp statement(assigns) do
    ~H"""
    <div id={"statement-#{@index}"} class="border-t border-base-content/10 first:border-t-0">
      <div class="grid gap-4 px-6 py-4 sm:grid-cols-2 sm:items-start">
        <div class="text-sm">
          <p class="text-base-content/70">Konto in der Datei</p>
          <p class="font-medium wrap-anywhere">{@item.statement.acct_id}</p>
          <p :if={@item.statement.bank_id} class="text-base-content/70">
            BLZ {@item.statement.bank_id}
          </p>
          <p
            :if={@item.statement.ledger_balance}
            id={"statement-#{@index}-balance"}
            class="text-base-content/70"
          >
            Banksaldo laut Datei: <.amount value={@item.statement.ledger_balance.amount} />
            am {Format.date(@item.statement.ledger_balance.date)}
          </p>
        </div>
        <form id={"statement-#{@index}-form"} phx-change="choose_account">
          <input type="hidden" name="index" value={@index} />
          <.input
            type="select"
            id={"statement-#{@index}-account"}
            name="account_id"
            label="Abakus-Konto"
            options={Enum.map(@accounts, &{&1.name, &1.id})}
            prompt={!@item.account && "Konto wählen …"}
            value={@item.account && @item.account.id}
          />
        </form>
      </div>
      <div class="flex flex-wrap gap-2 px-6 pb-4">
        <.badge id={"statement-#{@index}-new"} tone={:success}>{@item.preview.new} neu</.badge>
        <.badge :if={@item.preview.matched > 0} id={"statement-#{@index}-matched"} tone={:info}>
          {matched_label(@item.preview.matched)}
        </.badge>
        <.badge id={"statement-#{@index}-existing"}>
          {@item.preview.existing} bereits vorhanden
        </.badge>
        <.badge :if={@item.preview.reconciled > 0} id={"statement-#{@index}-reconciled"}>
          {@item.preview.reconciled} vor dem letzten Abgleich
        </.badge>
      </div>
      <.table
        :if={@item.preview.rows != []}
        id={"statement-#{@index}-rows"}
        rows={@item.preview.rows}
        size={:sm}
        flush
        row_attrs={&row_attrs/1}
      >
        <:col :let={row} label="Datum" show_from={:sm} class="whitespace-nowrap">
          {Format.date(row.transaction.date)}
        </:col>
        <:col :let={row} label="Empfänger">
          {row.transaction.name}
          <.cell_sub hide_from={:sm}>
            {join_meta([Format.date(row.transaction.date), status_label(row.status)])}
          </.cell_sub>
          <.cell_sub :if={row.transaction.memo}>{row.transaction.memo}</.cell_sub>
          <.cell_sub :if={row.match}>
            {Components.match_text(row.match, @transfer_accounts)}
          </.cell_sub>
        </:col>
        <:col :let={row} label="Betrag" align={:end}>
          <.amount
            value={row.transaction.amount}
            signed
            class={row.transaction.amount > 0 && "text-success-ink"}
          />
        </:col>
        <:col :let={row} label="Status" show_from={:sm}>
          <.badge tone={status_tone(row.status)}>{status_label(row.status)}</.badge>
        </:col>
      </.table>
    </div>
    """
  end

  defp row_attrs(%{status: status}),
    do: %{
      "data-status": status,
      class: status in [:existing, :reconciled] && "text-base-content/70"
    }

  defp status_label(:new), do: "neu"
  defp status_label(:matched), do: "Zuordnungsvorschlag"
  defp status_label(:existing), do: "vorhanden"
  defp status_label(:reconciled), do: "vor Abgleich"

  defp status_tone(:new), do: :success
  defp status_tone(:matched), do: :info
  defp status_tone(_status), do: :neutral

  defp upload_errors, do: @upload_errors

  defp transactions_text(1), do: "1 Buchung"
  defp transactions_text(count), do: "#{count} Buchungen"

  defp period([]), do: nil

  defp period(transactions) do
    {first, last} =
      transactions |> Enum.map(& &1.date) |> Enum.min_max_by(&Date.to_gregorian_days/1)

    "#{Format.date(first)}–#{Format.date(last)}"
  end

  defp matched_label(1), do: "1 Zuordnungsvorschlag"
  defp matched_label(count), do: "#{count} Zuordnungsvorschläge"

  defp import_label(0), do: "Importieren"
  defp import_label(1), do: "1 Buchung importieren"
  defp import_label(count), do: "#{count} Buchungen importieren"

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(
       page_title: "Import & Sync",
       preview: nil,
       accounts: FileImport.accounts(),
       transfer_accounts: %{}
     )
     |> allow_upload(:file,
       accept: ~w(.ofx .qfx),
       max_entries: 1,
       max_file_size: @max_file_size,
       auto_upload: true,
       progress: &handle_progress/3
     )}
  end

  defp handle_progress(:file, %{done?: true} = entry, socket) do
    content =
      consume_uploaded_entry(socket, entry, fn %{path: path} -> {:ok, File.read!(path)} end)

    case FileImport.read(content) do
      {:ok, statements} ->
        {:noreply,
         socket
         |> clear_flash()
         |> assign(:transfer_accounts, Map.new(Ledger.list_accounts(), &{&1.id, &1}))
         |> assign(:preview, %{
           file_name: entry.client_name,
           statements: Enum.map(statements, &item/1)
         })}

      {:error, message} ->
        {:noreply, socket |> assign(:preview, nil) |> put_flash(:error, message)}
    end
  end

  defp handle_progress(:file, _entry, socket), do: {:noreply, socket}

  defp item(statement, account \\ nil) do
    account = account || FileImport.linked_account(statement)
    %{statement: statement, account: account, preview: FileImport.preview(statement, account)}
  end

  @impl true
  def handle_event("validate", _params, socket), do: {:noreply, socket}

  def handle_event("choose_account", %{"index" => index, "account_id" => id}, socket) do
    with %{} = preview <- socket.assigns.preview,
         {index, ""} <- Integer.parse(index),
         %{} = item <- Enum.at(preview.statements, index) do
      account = Enum.find(socket.assigns.accounts, &(Integer.to_string(&1.id) == id))

      statements =
        List.replace_at(preview.statements, index, item(item.statement, account))

      {:noreply, assign(socket, :preview, %{preview | statements: statements})}
    else
      _other -> {:noreply, socket}
    end
  end

  def handle_event("discard", _params, socket), do: {:noreply, assign(socket, :preview, nil)}

  def handle_event("import", _params, %{assigns: %{preview: %{statements: statements}}} = socket) do
    if Enum.all?(statements, & &1.account) do
      statements
      |> Enum.map(&{&1.statement, &1.account})
      |> FileImport.import()
      |> imported(statements, socket)
    else
      {:noreply, socket}
    end
  end

  def handle_event("import", _params, socket), do: {:noreply, socket}

  defp imported({:ok, counts}, statements, socket) do
    {:noreply,
     socket
     |> put_flash(:info, imported_text(counts, statements))
     |> push_navigate(to: register_path(statements))}
  end

  defp imported({:error, reason}, _statements, socket) do
    accounts = FileImport.accounts()
    preview = socket.assigns.preview

    {:noreply,
     socket
     |> assign(
       accounts: accounts,
       preview: %{preview | statements: Enum.map(preview.statements, &refreshed(&1, accounts))}
     )
     |> put_flash(:error, "Nicht importiert: #{error_text(reason)}")}
  end

  # A chosen account stays while it is still offered.
  defp refreshed(%{statement: statement, account: account}, accounts),
    do: item(statement, Enum.find(accounts, &(&1.id == account.id)))

  defp error_text({transaction, changeset}),
    do:
      "Buchung vom #{Format.date(transaction.date)} (FITID #{transaction.fitid}): " <>
        TransactionEditor.error_message(changeset)

  defp error_text(reason), do: TransactionEditor.error_message(reason)

  defp imported_text(%{new: new, matched: matched}, statements) do
    count = new + matched

    balance =
      if Enum.any?(statements, & &1.statement.ledger_balance),
        do: " Banksaldo aus der Datei gemerkt."

    "#{count_text(count)}#{matched_text(matched)}#{target_text(count, statements)}.#{balance}"
  end

  defp matched_text(0), do: ""
  defp matched_text(1), do: ", 1 davon passt zu einer vorhandenen Buchung"
  defp matched_text(count), do: ", #{count} davon passen zu vorhandenen Buchungen"

  defp target_text(count, [%{account: account}]) when count > 0,
    do: ", zur Bestätigung in #{account.name}"

  defp target_text(_count, _statements), do: ""

  defp count_text(0), do: "Keine neuen Buchungen"
  defp count_text(1), do: "1 Buchung importiert"
  defp count_text(count), do: "#{count} Buchungen importiert"

  defp register_path([%{account: account}]), do: ~p"/budget/accounts/#{account}"
  defp register_path(_statements), do: ~p"/budget/accounts/all"
end
