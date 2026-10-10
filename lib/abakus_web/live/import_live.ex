defmodule AbakusWeb.ImportLive do
  @moduledoc """
  Import & Sync, for now the file import: a chosen OFX/QFX file is read at once and previewed per statement, with
  the file's account, the bank balance it reports, the account it goes into and its transactions: new, there
  already, a match proposal for a transaction in the register, or before the last reconcile (skipped). A file
  account seen before has its linked account chosen; an unknown one asks for the account. The import remembers the
  chosen one, so choosing another moves the link. Accounts fed by another app and closed ones are not offered. The
  preview lives in the LiveView only; the import checks again what is there.
  """
  use AbakusWeb, :live_view

  alias Abakus.{FileImport, Ledger}
  alias AbakusWeb.Format
  alias AbakusWeb.RegisterLive.{Components, TransactionEditor}

  @max_file_size 5_000_000

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      current={:import}
      account_groups={@account_groups}
      account_dialog={@account_dialog}
    >
      <h1 class="h2 mb-0">Import &amp; Sync</h1>
      <p class="small text-body-secondary mb-3">
        Umsätze aus dem Bank-Export (OFX oder QFX). Konten, die eine andere App füllt, nehmen keinen Datei-Import.
      </p>
      <div class="row g-4">
        <div class="col-lg-4 d-flex flex-column gap-3">
          <form id="import-form" phx-change="validate" phx-submit="validate">
            <label
              class="app-drop d-flex flex-column align-items-center justify-content-center text-center gap-2 p-4 mb-0"
              for={@uploads.file.ref}
            >
              <.icon name="upload" class="app-icon-lg" />
              <span class="fw-semibold">QFX- oder OFX-Datei wählen</span>
              <span class="small text-body-secondary">
                In der Banking-App die Umsätze des Kontos als OFX oder QFX exportieren
              </span>
              <.live_file_input
                upload={@uploads.file}
                accept=".ofx,.qfx"
                class="form-control form-control-sm mt-2"
              />
            </label>
          </form>
          <p :for={error <- upload_problems(@uploads.file)} class="small text-danger mb-0">
            {upload_error(error)}
          </p>
          <p class="small text-body-secondary mb-0">
            Buchungen, die schon da sind, erkennt Abakus an der FITID der Bank.
          </p>
        </div>
        <div :if={@preview} class="col-lg-8">
          <.preview preview={@preview} accounts={@accounts} transfer_accounts={@transfer_accounts} />
        </div>
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
    <section id="import-preview" class="card" aria-labelledby="import-file">
      <div class="card-header d-flex flex-wrap align-items-center gap-2">
        <.icon name="file" />
        <span id="import-file" class="fw-semibold me-auto text-break">{@preview.file_name}</span>
        <span class="small text-body-secondary">
          {transactions_text(length(@transactions))}{period(@transactions)}
        </span>
      </div>
      <.statement
        :for={{item, index} <- Enum.with_index(@preview.statements)}
        item={item}
        index={index}
        accounts={@accounts}
        transfer_accounts={@transfer_accounts}
      />
      <div class="card-footer d-flex flex-wrap align-items-center gap-2">
        <span class="small text-body-secondary me-auto">
          Neue Buchungen landen unbestätigt im Konto, Zuordnungsvorschläge warten auf Zuordnen oder Trennen.
        </span>
        <button id="import-discard" type="button" class="btn btn-sm" phx-click="discard">
          Verwerfen
        </button>
        <button
          id="import-submit"
          type="button"
          class="btn btn-sm btn-primary"
          phx-click="import"
          disabled={!@ready}
        >
          {import_label(@incoming)}
        </button>
      </div>
    </section>
    """
  end

  attr :item, :map, required: true
  attr :index, :integer, required: true
  attr :accounts, :list, required: true
  attr :transfer_accounts, :map, required: true, doc: "every account by id, naming transfers"

  defp statement(assigns) do
    ~H"""
    <div id={"statement-#{@index}"} class="border-bottom">
      <div class="card-body d-flex flex-column gap-3">
        <div class="d-flex flex-wrap gap-2">
          <span id={"statement-#{@index}-new"} class="badge text-bg-success">
            {@item.preview.new} neu
          </span>
          <span
            :if={@item.preview.matched > 0}
            id={"statement-#{@index}-matched"}
            class="badge text-bg-info"
          >
            {matched_label(@item.preview.matched)}
          </span>
          <span id={"statement-#{@index}-existing"} class="badge text-bg-secondary">
            {@item.preview.existing} bereits vorhanden
          </span>
          <span
            :if={@item.preview.reconciled > 0}
            id={"statement-#{@index}-reconciled"}
            class="badge text-bg-secondary"
          >
            {@item.preview.reconciled} vor dem letzten Abgleich
          </span>
        </div>
        <div class="row g-2 align-items-center">
          <div class="col-sm-6 small">
            Konto in der Datei
            <div class="fw-semibold text-break">{@item.statement.acct_id}</div>
            <div :if={@item.statement.bank_id} class="text-body-secondary">
              BLZ {@item.statement.bank_id}
            </div>
            <div
              :if={@item.statement.ledger_balance}
              id={"statement-#{@index}-balance"}
              class="text-body-secondary"
            >
              Banksaldo laut Datei:
              <span class="tabular-nums text-nowrap">
                {Format.euros(@item.statement.ledger_balance.amount)}
              </span>
              am {Format.date(@item.statement.ledger_balance.date)}
            </div>
          </div>
          <div class="col-sm-6">
            <form id={"statement-#{@index}-form"} phx-change="choose_account">
              <input type="hidden" name="index" value={@index} />
              <label class="form-label small mb-1" for={"statement-#{@index}-account"}>
                Abakus-Konto
              </label>
              <select
                id={"statement-#{@index}-account"}
                name="account_id"
                class="form-select form-select-sm"
              >
                <option :if={!@item.account} value="">Konto wählen …</option>
                <option
                  :for={account <- @accounts}
                  value={account.id}
                  selected={@item.account && @item.account.id == account.id}
                >
                  {account.name}
                </option>
              </select>
            </form>
          </div>
        </div>
      </div>
      <div :if={@item.preview.rows != []} class="table-responsive">
        <table class="table table-sm align-middle mb-0 tabular-nums">
          <thead>
            <tr>
              <th scope="col">Datum</th>
              <th scope="col">Empfänger</th>
              <th scope="col" class="text-end">Betrag</th>
              <th scope="col">Status</th>
            </tr>
          </thead>
          <tbody>
            <tr
              :for={%{transaction: transaction, status: status} = row <- @item.preview.rows}
              class={status in [:existing, :reconciled] && "text-body-secondary"}
            >
              <td class="text-nowrap">{Format.date(transaction.date)}</td>
              <td>
                {transaction.name}
                <div :if={transaction.memo} class="small text-body-secondary">{transaction.memo}</div>
                <div :if={row.match} class="small text-info-emphasis">
                  {Components.match_text(row.match, @transfer_accounts)}
                </div>
              </td>
              <td class={["text-end text-nowrap", transaction.amount > 0 && "text-success"]}>
                {Format.signed_euros(transaction.amount)}
              </td>
              <td>
                <span :if={status == :new} class="badge text-bg-success">neu</span>
                <span :if={status == :matched} class="badge text-bg-info">Zuordnungsvorschlag</span>
                <span :if={status == :existing} class="badge text-bg-secondary">vorhanden</span>
                <span :if={status == :reconciled} class="badge text-bg-secondary">vor Abgleich</span>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>
    """
  end

  defp transactions_text(1), do: "1 Buchung"
  defp transactions_text(count), do: "#{count} Buchungen"

  defp period([]), do: ""

  defp period(transactions) do
    {first, last} =
      transactions |> Enum.map(& &1.date) |> Enum.min_max_by(&Date.to_gregorian_days/1)

    " · #{Format.date(first)}–#{Format.date(last)}"
  end

  defp matched_label(1), do: "1 Zuordnungsvorschlag"
  defp matched_label(count), do: "#{count} Zuordnungsvorschläge"

  defp import_label(0), do: "Importieren"
  defp import_label(1), do: "1 Buchung importieren"
  defp import_label(count), do: "#{count} Buchungen importieren"

  defp upload_problems(upload),
    do: upload_errors(upload) ++ Enum.flat_map(upload.entries, &upload_errors(upload, &1))

  defp upload_error(:too_large), do: "Die Datei ist größer als 5 MB."
  defp upload_error(:too_many_files), do: "Bitte nur eine Datei wählen."
  defp upload_error(_error), do: "Die Datei ließ sich nicht hochladen."

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
       accept: :any,
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

  defp register_path([%{account: account}]), do: ~p"/accounts/#{account}"
  defp register_path(_statements), do: ~p"/accounts/all"
end
