defmodule AbakusWeb.Depot.TransactionDialog do
  @moduledoc """
  The dialog „Buchung erfassen“ on the Depot's pages, opened by `open/0` from the sidebar entry of
  that name (also in the rail), the Buchungen page and the phone's button: a purchase, sale,
  dividend, deposit or removal with an optional PDF receipt. The amount follows the other fields
  until the user overwrites it. A security missing from the list is created by its ISIN, with name
  and Yahoo symbol from Yahoo's search.

  `edit/1` opens it for a transaction of the user: as „Buchung bearbeiten“, which saves or deletes
  it, for a type the form knows, otherwise as „Buchung“, which shows and only deletes it.
  `open_receipt/1` opens it as „Beleg prüfen“ for a receipt of the inbox, prefilled with what the
  model recognised, beside the receipt's checks and text; booking attaches the receipt, which may
  also be discarded or left for later. Once booked, every page loads its figures again,
  and the page shows what was booked:
  components cannot show a flash themselves, so `on_mount/4` lets the page do it.
  """
  use AbakusWeb, :live_component

  import AbakusWeb.Depot.Components

  alias Abakus.Depot.{MarketData, Portfolios, Receipts, Securities}
  alias Abakus.Depot.Portfolios.{Transaction, TransactionForm}
  alias Abakus.Depot.Receipts.{Checks, Fields}
  alias Abakus.Depot.Securities.ISIN
  alias Abakus.LocalTime
  alias Abakus.Money
  alias AbakusWeb.Depot.{Format, ReceiptComponents}

  @id "transaction-dialog"
  @kinds [
    purchase: "Kauf",
    sale: "Verkauf",
    dividend: "Dividende",
    deposit: "Einlage",
    removal: "Entnahme"
  ]

  @receipt_gone "Dieser Beleg liegt nicht mehr im Eingang."

  @holding_error "Ohne diese Buchung fiele der Bestand später unter null. " <>
                   "Bitte zuerst die späteren Verkäufe ändern."

  @doc "The id the layout renders the dialog with."
  def id, do: @id

  @doc "Opens the dialog."
  def open, do: JS.push("open", target: "##{@id}")

  @doc "Opens the dialog for the user's transaction with `id`."
  def edit(id), do: JS.push("edit", value: %{id: id}, target: "##{@id}")

  @doc "Opens the dialog for the receipt with `id`, one ready in the user's inbox."
  def open_receipt(id), do: JS.push("open_receipt", value: %{id: id}, target: "##{@id}")

  @doc "Shows the dialog's message on the page that renders it."
  def on_mount(:default, _params, _session, socket),
    do: {:cont, Phoenix.LiveView.attach_hook(socket, :transaction_dialog, :handle_info, &flash/2)}

  defp flash({__MODULE__, :done, message}, socket),
    do: {:halt, put_flash(socket, :info, message)}

  defp flash(_message, socket), do: {:cont, socket}

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> assign(open: false, editing: nil, receipt: nil, new_security: nil, error: nil)
     |> allow_upload(:receipt, accept: ~w(.pdf), max_entries: 1, max_file_size: 20_000_000)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id}>
      <.modal
        :if={@open}
        id="transaction-modal"
        title={title(@receipt, @editing)}
        show
        on_cancel={JS.push("close", target: @myself)}
        class={if @receipt, do: "sm:max-w-6xl", else: "sm:max-w-2xl"}
      >
        <p :if={@receipt} class="text-sm text-base-content/70 wrap-anywhere">
          {ReceiptComponents.receipt_subtitle(@receipt)}
        </p>
        <.read_only
          :if={read_only?(@editing)}
          transaction={@editing}
          error={@error}
          myself={@myself}
        />
        <.form
          :if={!read_only?(@editing)}
          for={@form}
          id="transaction-form"
          class="mt-4"
          phx-change="validate"
          phx-submit="book"
          phx-target={@myself}
        >
          <input :if={@receipt} type="hidden" name="receipt_id" value={@receipt.id} />
          <div class={@receipt && "grid gap-6 lg:grid-cols-[3fr_2fr]"}>
            <div :if={@receipt} class="app-receipt-pane min-w-0">
              <ReceiptComponents.sheet receipt={@receipt} />
            </div>
            <div class="min-w-0">
              <ReceiptComponents.checklist :if={@receipt} receipt={@receipt} />
              <.kinds field={@form[:kind]} receipt={@receipt} />
              <.fields
                form={@form}
                kind={@kind}
                choices={@choices}
                receipt={@receipt}
                editing={@editing}
                today={@today}
                new_security={@new_security}
                depot_number_warning={@depot_number_warning}
                uploads={@uploads}
                myself={@myself}
              />
            </div>
          </div>
          <.alert
            :if={@error}
            id="transaction-error"
            tone={:error}
            class="mt-4"
          >
            {@error}
          </.alert>
          <.action_bar :if={@receipt} sticky class="mt-6">
            <:secondary>
              <.button
                id="receipt-discard"
                variant={:ghost}
                phx-click="discard_receipt"
                phx-target={@myself}
              >
                Verwerfen
              </.button>
            </:secondary>
            <.button id="receipt-later" phx-click={close_js()}>Später</.button>
            <.button
              id="transaction-book"
              type="submit"
              name="intent"
              value="book"
              variant={:primary}
              phx-disable-with="Wird gebucht …"
            >
              Buchen
            </.button>
          </.action_bar>
          <.action_bar :if={!@receipt} sticky class="mt-6">
            <:secondary :if={@editing}>
              <.button
                id="transaction-delete"
                variant={:danger_outline}
                icon="trash-2"
                confirm="Diese Buchung löschen?"
                phx-click={JS.push("delete", target: @myself)}
              >
                Löschen
              </.button>
            </:secondary>
            <.button id="transaction-cancel" phx-click={close_js()}>Abbrechen</.button>
            <.button
              id="transaction-book"
              type="submit"
              variant={:primary}
              name="intent"
              value="book"
              phx-disable-with={if @editing, do: "Wird gespeichert …", else: "Wird gebucht …"}
            >
              {if @editing, do: "Speichern", else: "Buchen"}
            </.button>
          </.action_bar>
        </.form>
      </.modal>
    </div>
    """
  end

  defp title(%{} = _receipt, _editing), do: "Beleg prüfen"
  defp title(nil, nil), do: "Buchung erfassen"

  defp title(nil, editing),
    do: if(read_only?(editing), do: "Buchung", else: "Buchung bearbeiten")

  defp read_only?(nil), do: false
  defp read_only?(editing), do: not Transaction.editable?(editing)

  # Closes natively, so focus goes back to what opened the dialog; `on_cancel` tells the server.
  defp close_js, do: hide_modal("transaction-modal")

  attr :transaction, Transaction, required: true
  attr :error, :string, required: true
  attr :myself, :any, required: true

  defp read_only(assigns) do
    assigns = assign(assigns, :facts, facts(assigns.transaction))

    ~H"""
    <div id="transaction-read-only" class="mt-4">
      <.description_list id="transaction-facts">
        <:item :for={{label, value} <- @facts} label={label}>{value}</:item>
      </.description_list>
      <p class="mt-4 text-sm text-base-content/70">Diese Buchungsart lässt sich nur löschen.</p>
      <.alert :if={@error} id="transaction-error" tone={:error} class="mt-4">{@error}</.alert>
      <.action_bar sticky class="mt-6">
        <:secondary>
          <.button
            id="transaction-delete"
            variant={:danger_outline}
            icon="trash-2"
            confirm="Diese Buchung löschen?"
            phx-click={JS.push("delete", target: @myself)}
          >
            Löschen
          </.button>
        </:secondary>
        <.button id="transaction-cancel" phx-click={close_js()}>Schließen</.button>
      </.action_bar>
    </div>
    """
  end

  defp facts(transaction) do
    Enum.reject(
      [
        {"Art", Format.transaction_type(transaction.type)},
        {"Datum", Abakus.Format.date(transaction.date_time)},
        transaction.security && {"Wertpapier", transaction.security.name}
      ] ++
        places(transaction) ++
        [
          transaction.shares not in [nil, 0] && {"Stück", Format.shares(transaction.shares)},
          {"Betrag", Money.money(transaction.amount, transaction.currency)},
          unit_fact(transaction, :fee, "Gebühren"),
          unit_fact(transaction, :tax, "Steuern"),
          transaction.note not in [nil, ""] && {"Notiz", transaction.note}
        ],
      &(!&1)
    )
  end

  defp places(%Transaction{type: :security_transfer} = transaction) do
    [
      {"Von Depot", portfolio_name(transaction.portfolio)},
      {"An Depot", portfolio_name(transaction.other_portfolio)}
    ]
  end

  defp places(%Transaction{type: :cash_transfer} = transaction) do
    [
      {"Von Konto", account_name(transaction.account)},
      {"An Konto", account_name(transaction.other_account)}
    ]
  end

  defp places(transaction) do
    [
      transaction.portfolio && {"Depot", portfolio_name(transaction.portfolio)},
      transaction.account && {"Konto", account_name(transaction.account)}
    ]
  end

  defp portfolio_name(nil), do: "–"
  defp portfolio_name(portfolio), do: Format.portfolio_name(portfolio)

  defp account_name(nil), do: "–"
  defp account_name(account), do: account.name

  defp unit_fact(transaction, type, label) do
    case transaction.units |> Enum.filter(&(&1.type == type)) |> Enum.sum_by(& &1.amount) do
      0 -> nil
      cents -> {label, Money.money(cents, transaction.currency)}
    end
  end

  attr :form, Phoenix.HTML.Form, required: true
  attr :kind, :atom, required: true
  attr :choices, :map, required: true
  attr :receipt, :any, required: true
  attr :editing, :any, required: true
  attr :today, Date, required: true
  attr :new_security, :any, required: true
  attr :depot_number_warning, :string, default: nil
  attr :uploads, :map, required: true
  attr :myself, :any, required: true

  defp fields(assigns) do
    assigns = assign(assigns, :security?, assigns.kind not in [:deposit, :removal])

    ~H"""
    <div class="mt-2 grid grid-cols-2 gap-x-4 sm:grid-cols-6">
      <div :if={@security?} class="col-span-2 sm:col-span-3">
        <.input
          field={@form[:portfolio_id]}
          type="select"
          label="Depot"
          options={Enum.map(@choices.portfolios, &{Format.portfolio_name(&1), &1.id})}
          prompt={portfolio_prompt(@kind, @receipt)}
          help={@depot_number_warning}
          help_tone={:warning}
        />
      </div>
      <div class={["col-span-2", if(@security?, do: "sm:col-span-3", else: "sm:col-span-6")]}>
        <.input field={@form[:date]} type="date" label="Datum" max={Date.to_iso8601(@today)} />
      </div>
      <div :if={@security?} class="col-span-2 sm:col-span-6">
        <.input
          field={@form[:security_id]}
          type="select"
          label="Wertpapier"
          options={Enum.map(@choices.securities, &{security_label(&1), &1.id})}
          prompt="Wertpapier wählen"
        />
        <.button
          :if={!@new_security and !(@receipt && @form[:security_id].value not in [nil, ""])}
          id="new-security"
          variant={:link}
          size={:sm}
          class="px-0"
          phx-click="new_security"
          phx-target={@myself}
        >
          Neues Wertpapier per ISIN
        </.button>
        <.new_security
          :if={@new_security}
          form={@new_security.form}
          lookup={@new_security.lookup}
          myself={@myself}
        />
      </div>
      <div :if={@security?} class="sm:col-span-2">
        <.number field={@form[:shares]} label="Stück" />
      </div>
      <div :if={@kind in [:purchase, :sale]} class="sm:col-span-2">
        <.number
          field={@form[:price]}
          label="Kurs"
          euros
          help={ReceiptComponents.price_warning(@receipt)}
          help_tone={:warning}
        />
      </div>
      <div :if={@kind == :dividend} class="sm:col-span-2">
        <.number field={@form[:gross]} label="Brutto" euros />
      </div>
      <div :if={@security?} class="sm:col-span-2">
        <.number field={@form[:fees]} label="Gebühren" euros />
      </div>
      <div :if={@security?} class="sm:col-span-2">
        <.number field={@form[:taxes]} label="Steuern" euros />
      </div>
      <div class="col-span-2 sm:col-span-4">
        <.input
          field={@form[:account_id]}
          type="select"
          label="Konto"
          options={Enum.map(@choices.accounts, &{&1.name, &1.id})}
          prompt={account_prompt(@kind)}
        />
      </div>
      <div class="col-span-2 sm:col-span-6">
        <.amount_field form={@form} kind={@kind} />
      </div>
      <div :if={@kind == :dividend and !@editing} class="col-span-2 sm:col-span-6">
        <.input
          field={@form[:remove_at_once]}
          type="checkbox"
          label="Gleich entnehmen"
          help="Bucht den Nettobetrag am selben Tag vom Konto ab."
        />
      </div>
      <div :if={!@receipt} class="col-span-2 sm:col-span-6">
        <.receipt_file uploads={@uploads} form={@form} editing={@editing} />
      </div>
    </div>
    """
  end

  attr :uploads, :map, required: true
  attr :form, Phoenix.HTML.Form, required: true
  attr :editing, :any, required: true

  defp receipt_file(assigns) do
    assigns =
      assign(assigns,
        ref: assigns.uploads.receipt.ref,
        errors: receipt_errors(assigns.uploads, assigns.form),
        attached: assigns.editing && assigns.editing.receipt
      )

    ~H"""
    <fieldset class="fieldset min-w-0">
      <label class="fieldset-legend" for={@ref}>
        {if @attached, do: "Beleg ersetzen", else: "Beleg"}
        <span class="font-normal text-base-content/70">(optional)</span>
      </label>
      <.live_file_input
        upload={@uploads.receipt}
        class={["file-input w-full", @errors != [] && "file-input-error"]}
        aria-invalid={@errors != [] && "true"}
        aria-describedby={field_describedby(@ref, @errors, @attached)}
      />
      <.field_error id={@ref} errors={@errors} />
      <.field_help :if={@attached} id={@ref}>
        Angehängt:
        <a
          href={~p"/depot/receipts/#{@editing.receipt_id}"}
          target="_blank"
          rel="noopener"
          class="link"
        >
          {@editing.receipt.filename}
        </a>
      </.field_help>
    </fieldset>
    """
  end

  attr :form, Phoenix.HTML.Form, required: true
  attr :lookup, :any, required: true, doc: "nil, `:searching`, `:found` or `{:error, message}`"
  attr :myself, :any, required: true

  # Inside the transaction form, as forms do not nest: its fields are sent as `security`. „Anlegen“
  # comes first of the form's submit buttons, so Enter while it shows creates the security.
  defp new_security(assigns) do
    assigns =
      assign(assigns,
        isin: assigns.form[:isin],
        isin_errors: field_errors(assigns.form[:isin])
      )

    ~H"""
    <fieldset
      id="new-security-panel"
      class="mt-2 rounded-box border border-base-content/10 px-4 pb-4"
    >
      <legend class="fieldset-legend px-1">Neues Wertpapier</legend>
      <div class="grid gap-x-4 sm:grid-cols-2">
        <fieldset class="fieldset min-w-0">
          <label class="fieldset-legend" for={@isin.id}>ISIN</label>
          <input
            type="text"
            id={@isin.id}
            name={@isin.name}
            value={@isin.value}
            autocomplete="off"
            spellcheck="false"
            phx-debounce="300"
            class={["input w-full uppercase font-mono", @isin_errors != [] && "input-error"]}
            aria-invalid={@isin_errors != [] && "true"}
            aria-describedby={field_describedby(@isin.id, @isin_errors, true)}
          />
          <.field_error id={@isin.id} errors={@isin_errors} />
          <.field_help id={@isin.id} aria-live="polite">
            {lookup_text(@lookup, @isin.value)}
          </.field_help>
        </fieldset>
        <.input field={@form[:name]} label="Name" autocomplete="off" />
        <.input
          field={@form[:symbol]}
          label="Yahoo-Symbol"
          help="Leer lassen ohne Kurse von Yahoo."
          autocomplete="off"
          spellcheck="false"
        />
        <div class="flex items-end justify-end gap-2 pt-2 sm:pb-7">
          <.button variant={:ghost} phx-click="cancel_security" phx-target={@myself}>
            Abbrechen
          </.button>
          <.button id="new-security-create" type="submit" name="intent" value="create_security">
            Anlegen
          </.button>
        </div>
      </div>
    </fieldset>
    """
  end

  defp lookup_text(nil, isin) when isin in [nil, ""],
    do: "Name und Symbol kommen aus Yahoos Suche."

  defp lookup_text(nil, _isin), do: nil
  defp lookup_text(:searching, _isin), do: "Suche bei Yahoo …"
  defp lookup_text(:found, _isin), do: "Von Yahoo übernommen, bitte prüfen."
  defp lookup_text({:error, message}, _isin), do: message

  attr :field, Phoenix.HTML.FormField, required: true
  attr :receipt, :any, required: true

  defp kinds(assigns) do
    kinds =
      if assigns.receipt, do: Keyword.take(@kinds, [:purchase, :sale, :dividend]), else: @kinds

    assigns = assign(assigns, :kinds, Enum.map(kinds, fn {kind, label} -> {label, kind} end))

    ~H"""
    <.segmented
      mode={:radio}
      field={@field}
      label="Art"
      size={:sm}
      options={@kinds}
      block
    />
    """
  end

  attr :field, Phoenix.HTML.FormField, required: true
  attr :label, :string, required: true
  attr :euros, :boolean, default: false
  attr :help, :string, default: nil, doc: "what a receipt's failed check says about it"
  attr :help_tone, :atom, default: nil

  defp number(assigns) do
    ~H"""
    <.input
      field={@field}
      label={@label}
      value={typed(@field)}
      numeric
      suffix={@euros && "€"}
      autocomplete="off"
      help={@help}
      help_tone={@help_tone}
    />
    """
  end

  attr :form, Phoenix.HTML.Form, required: true
  attr :kind, :atom, required: true

  defp amount_field(assigns) do
    form = assigns.form
    expected = form[:expected_amount].value

    assigns =
      assign(assigns,
        value: amount_value(form),
        help:
          expected &&
            "#{expected_text(assigns.kind, form)} ergibt #{Money.euros(cents(expected))}."
      )

    ~H"""
    <input type="hidden" name={@form[:amount_set].name} value={to_string(@form[:amount_set].value)} />
    <.input
      field={@form[:amount]}
      label={"Betrag (#{amount_hint(@kind, @form[:account_id].value)})"}
      value={@value}
      numeric
      suffix="€"
      autocomplete="off"
      class="font-semibold"
      help={@help}
      help_tone={:warning}
    />
    """
  end

  # Untranslated: `field_error` translates them.
  defp field_errors(field),
    do: if(Phoenix.Component.used_input?(field), do: field.errors, else: [])

  # What the user typed, not the cast decimal, which would read as thousands in German.
  defp typed(%Phoenix.HTML.FormField{form: form, field: field}),
    do: Map.get(form.params, Atom.to_string(field))

  defp amount_value(form) do
    case {form[:amount_set].value, form[:amount].value} do
      {true, _amount} -> typed(form[:amount])
      {_computed, %Decimal{} = amount} -> Money.amount(cents(amount))
      {_computed, _none} -> nil
    end
  end

  defp cents(decimal), do: decimal |> Decimal.mult(100) |> Decimal.to_integer()

  defp security_label(%{isin: isin} = security) when isin in [nil, ""], do: security.name
  defp security_label(security), do: "#{security.name} (#{security.isin})"

  defp portfolio_prompt(:dividend, _receipt), do: "Ohne Depot"
  defp portfolio_prompt(_kind, nil), do: nil
  defp portfolio_prompt(_kind, _receipt), do: "Depot wählen"

  defp account_prompt(:purchase), do: "Ohne Konto (Einlieferung)"
  defp account_prompt(:sale), do: "Ohne Konto (Auslieferung)"
  defp account_prompt(_kind), do: "Konto wählen"

  defp amount_hint(kind, account_id) when kind in [:purchase, :sale] and account_id in [nil, ""],
    do: "ohne Konto"

  defp amount_hint(kind, _account_id) when kind in [:purchase, :removal],
    do: "wird vom Konto abgebucht"

  defp amount_hint(:dividend, _account_id), do: "netto, wird dem Konto gutgeschrieben"
  defp amount_hint(_kind, _account_id), do: "wird dem Konto gutgeschrieben"

  defp expected_text(:dividend, _form), do: "Brutto abzüglich Gebühren und Steuern"

  defp expected_text(_kind, form) do
    if zero?(form[:fees].value) and zero?(form[:taxes].value),
      do: "Stück × Kurs",
      else: "Stück × Kurs mit Gebühren und Steuern"
  end

  defp zero?(%Decimal{} = value), do: Decimal.eq?(value, 0)
  defp zero?(_blank), do: true

  defp receipt_errors(uploads, form) do
    upload = uploads.receipt
    entry_errors = Enum.flat_map(upload.entries, &upload_errors(upload, &1))

    Enum.map(upload_errors(upload) ++ entry_errors, &upload_error/1) ++ form[:receipt].errors
  end

  defp upload_error(:too_large), do: "Die Datei ist zu groß."
  defp upload_error(:not_accepted), do: "Bitte eine PDF-Datei wählen."
  defp upload_error(:too_many_files), do: "Bitte nur eine Datei wählen."
  defp upload_error(_error), do: "Die Datei ließ sich nicht hochladen."

  @impl true
  def handle_event("open", _params, socket) do
    scope = socket.assigns.current_scope
    choices = Portfolios.transaction_choices(scope)
    portfolio = List.first(choices.portfolios)

    params = %{
      "kind" => "purchase",
      "date" => Date.to_iso8601(LocalTime.today()),
      "portfolio_id" => portfolio && to_string(portfolio.id),
      "account_id" => reference_account(choices, portfolio && portfolio.id),
      "fees" => "0,00",
      "taxes" => "0,00"
    }

    {:noreply,
     socket
     |> assign(open: true, editing: nil, receipt: nil, new_security: nil, error: nil)
     |> assign(choices: choices, today: LocalTime.today())
     |> put_form(Portfolios.change_transaction_form(scope, choices, params))}
  end

  def handle_event("open_receipt", %{"id" => id}, socket) do
    case Receipts.get_ready_receipt(socket.assigns.current_scope, id) do
      nil -> done(socket, @receipt_gone)
      receipt -> {:noreply, open_receipt_for(socket, receipt)}
    end
  end

  def handle_event("discard_receipt", _params, %{assigns: %{receipt: %{} = receipt}} = socket) do
    case Receipts.discard(socket.assigns.current_scope, receipt.id) do
      :ok -> socket |> close() |> done("Beleg verworfen.")
      {:error, :gone} -> socket |> close() |> done(@receipt_gone)
    end
  end

  # A click that comes after the receipt has left the dialog.
  def handle_event("discard_receipt", _params, socket), do: {:noreply, close(socket)}

  def handle_event("edit", %{"id" => id}, socket) do
    scope = socket.assigns.current_scope

    case Portfolios.get_transaction(scope, id) do
      nil ->
        done(socket, "Diese Buchung gibt es nicht mehr.")

      transaction ->
        {:noreply, open_for(socket, transaction)}
    end
  end

  def handle_event("close", _params, socket), do: {:noreply, close(socket)}

  def handle_event("validate", %{"transaction" => params} = event, socket) do
    params = follow(params, event["_target"], socket.assigns.choices)
    changeset = socket |> change_form(params) |> Map.put(:action, :validate)

    {:noreply,
     socket
     |> assign(:error, nil)
     |> put_form(changeset)
     |> change_new_security(event["security"], event["_target"])}
  end

  def handle_event("book", %{"intent" => "create_security"}, socket) do
    if socket.assigns.new_security,
      do: create_security(socket),
      else: {:noreply, socket}
  end

  def handle_event(
        "book",
        %{"transaction" => params},
        %{assigns: %{receipt: %{} = receipt}} = socket
      ) do
    %{current_scope: scope, choices: choices} = socket.assigns

    case Receipts.book(scope, choices, params, receipt) do
      {:error, :gone} -> socket |> close() |> done(@receipt_gone)
      result -> saved(result, socket)
    end
  end

  # A submit that comes after the dialog closed or its receipt left it books nothing.
  def handle_event("book", _params, %{assigns: %{open: false}} = socket),
    do: {:noreply, socket}

  def handle_event("book", %{"receipt_id" => _id}, socket), do: {:noreply, close(socket)}

  def handle_event("book", %{"transaction" => params}, socket) do
    changeset = change_form(socket, params)

    cond do
      not changeset.valid? ->
        {:noreply, put_form(socket, Map.put(changeset, :action, :insert))}

      match?({_done, [_ | _]}, uploaded_entries(socket, :receipt)) ->
        {:noreply, socket}

      true ->
        socket |> save(params) |> recheck_inbox(socket) |> saved(socket)
    end
  end

  def handle_event("delete", _params, %{assigns: %{editing: %{} = transaction}} = socket) do
    scope = socket.assigns.current_scope

    case Portfolios.delete_transaction(scope, transaction) do
      {:ok, _deleted} ->
        Receipts.recheck(scope)
        socket |> close() |> done("Buchung gelöscht.")

      {:error, :read_only} ->
        {:noreply, close(socket)}

      {:error, :holding} ->
        {:noreply, assign(socket, :error, @holding_error)}

      {:error, message} when is_binary(message) ->
        {:noreply, assign(socket, :error, message)}
    end
  end

  def handle_event("new_security", _params, socket) do
    {:noreply,
     assign(socket, :new_security, %{form: security_form(%{}, nil), lookup: nil, isin: nil})}
  end

  def handle_event("cancel_security", _params, socket),
    do: {:noreply, assign(socket, :new_security, nil)}

  @impl true
  def handle_async(:lookup, result, %{assigns: %{new_security: %{} = new_security}} = socket) do
    {:noreply, assign(socket, :new_security, looked_up(new_security, result))}
  end

  def handle_async(:lookup, _result, socket), do: {:noreply, socket}

  defp open_for(socket, transaction) do
    socket =
      assign(socket,
        open: true,
        editing: transaction,
        receipt: nil,
        new_security: nil,
        error: nil
      )

    if Transaction.editable?(transaction),
      do: open_form_for(socket, transaction),
      else: socket
  end

  defp open_form_for(socket, transaction) do
    scope = socket.assigns.current_scope
    choices = Portfolios.transaction_choices(scope, transaction)
    params = Portfolios.transaction_form_params(transaction)

    socket
    |> assign(choices: choices, today: LocalTime.today())
    |> put_form(Portfolios.change_transaction_form(scope, choices, params, transaction))
  end

  # The portfolio is the one of the receipt's depot number, with its reference account; the user
  # picks it for an unknown depot number. An unknown ISIN opens „Neues Wertpapier“ with it.
  defp open_receipt_for(socket, receipt) do
    scope = socket.assigns.current_scope
    choices = Portfolios.transaction_choices(scope)
    portfolio_id = receipt_portfolio_id(choices, receipt)

    params =
      %{
        "kind" => "purchase",
        "date" => Date.to_iso8601(LocalTime.today()),
        "fees" => "0,00",
        "taxes" => "0,00"
      }
      |> Map.merge(receipt_params(receipt.fields), fn _key, default, value -> value || default end)
      |> Map.merge(%{
        "portfolio_id" => portfolio_id && to_string(portfolio_id),
        "account_id" => reference_account(choices, portfolio_id),
        "security_id" => security_id(choices, receipt.fields)
      })

    socket
    |> assign(open: true, editing: nil, receipt: receipt, new_security: nil, error: nil)
    |> assign(choices: choices, today: LocalTime.today())
    |> put_form(Portfolios.change_transaction_form(scope, choices, params))
    |> open_new_security(receipt.fields, params["security_id"])
  end

  # Without a depot number on the receipt, a user with one portfolio needs no choice.
  defp receipt_portfolio_id(choices, receipt) do
    case {Checks.portfolio(receipt.checks), choices.portfolios} do
      {{id, _name}, portfolios} -> if Enum.any?(portfolios, &(&1.id == id)), do: id
      {nil, [only]} -> if depot_number_check(receipt) in [nil, :missing], do: only.id
      {nil, _none_or_many} -> nil
    end
  end

  defp depot_number_check(receipt) do
    Enum.find_value(receipt.checks, &(&1.name == :depot && &1.result))
  end

  defp receipt_params(nil), do: %{}
  defp receipt_params(fields), do: TransactionForm.params_of_receipt(fields)

  defp security_id(_choices, nil), do: ""

  defp security_id(choices, %Fields{isin: isin}) do
    case Enum.find(choices.securities, &(&1.isin == isin and isin != nil)) do
      nil -> ""
      security -> to_string(security.id)
    end
  end

  defp open_new_security(socket, %Fields{kind: kind, isin: isin} = fields, "")
       when kind in [:purchase, :sale, :dividend] and is_binary(isin) do
    params = %{"isin" => isin, "name" => fields.security_name || ""}
    new_security = %{form: security_form(params, nil), lookup: nil, isin: nil}

    socket
    |> assign(:new_security, new_security)
    |> change_new_security(params, ["security", "isin"])
  end

  defp open_new_security(socket, _fields, _security_id), do: socket

  defp change_form(socket, params) do
    %{current_scope: scope, choices: choices, editing: editing} = socket.assigns
    Portfolios.change_transaction_form(scope, choices, params, editing)
  end

  defp security_form(params, action) do
    params
    |> Securities.change_new_security()
    |> Map.put(:action, action)
    |> to_form(as: :security)
  end

  # A new, valid ISIN is looked up at Yahoo; its name and symbol replace what is in the fields.
  defp change_new_security(
         %{assigns: %{new_security: %{} = new_security}} = socket,
         params,
         target
       )
       when is_map(params) do
    isin = params |> Map.get("isin", "") |> String.replace(" ", "") |> String.upcase()
    lookup? = target == ["security", "isin"] and isin != new_security.isin and ISIN.valid?(isin)
    new_security = %{new_security | form: security_form(params, :validate)}

    if lookup? do
      socket
      |> assign(:new_security, %{new_security | isin: isin, lookup: :searching})
      |> start_async(:lookup, fn -> {isin, MarketData.lookup_isin(isin)} end)
    else
      assign(socket, :new_security, new_security)
    end
  end

  defp change_new_security(socket, _params, _target), do: socket

  defp looked_up(%{isin: isin} = new_security, {:ok, {isin, {:ok, found}}}) do
    params =
      new_security.form.params
      |> Map.put("isin", isin)
      |> Map.merge(%{"name" => found.name, "symbol" => found.symbol})

    %{new_security | form: security_form(params, :validate), lookup: :found}
  end

  defp looked_up(%{isin: isin} = new_security, {:ok, {isin, {:error, reason}}}),
    do: %{new_security | lookup: {:error, MarketData.lookup_error(reason)}}

  defp looked_up(new_security, {:exit, _reason}),
    do: %{new_security | lookup: {:error, MarketData.lookup_error(:unreachable)}}

  # The answer for an ISIN typed over meanwhile.
  defp looked_up(new_security, _stale), do: new_security

  defp create_security(socket) do
    %{current_scope: scope, new_security: new_security, editing: editing} = socket.assigns

    case Securities.create_security(scope, new_security.form.params) do
      {:ok, security} ->
        if security.quote_feed == :yahoo, do: MarketData.fetch_in_background(security)
        Receipts.recheck(scope)
        choices = Portfolios.transaction_choices(scope, editing)
        socket = assign(socket, choices: choices, new_security: nil) |> recheck_receipt()
        params = Map.put(socket.assigns.form.params, "security_id", to_string(security.id))
        {:noreply, put_form(socket, Map.put(change_form(socket, params), :action, :validate))}

      {:error, changeset} ->
        form = to_form(changeset, as: :security)
        {:noreply, assign(socket, :new_security, %{new_security | form: form})}
    end
  end

  # The account follows the portfolio; an amount typed in stays until it is emptied.
  defp follow(params, ["transaction", "portfolio_id"], choices),
    do:
      Map.put(params, "account_id", reference_account(choices, parse_id(params["portfolio_id"])))

  defp follow(params, ["transaction", "amount"], _choices),
    do: Map.put(params, "amount_set", to_string(String.trim(params["amount"] || "") != ""))

  defp follow(params, _target, _choices), do: params

  defp reference_account(choices, portfolio_id) do
    with %{reference_account_id: id} when id != nil <-
           Enum.find(choices.portfolios, &(&1.id == portfolio_id)),
         true <- Enum.any?(choices.accounts, &(&1.id == id)) do
      to_string(id)
    else
      _none -> ""
    end
  end

  defp save(socket, params) do
    case consume_uploaded_entries(socket, :receipt, fn %{path: path}, entry ->
           {:ok, save(socket, params, {path, entry.client_name})}
         end) do
      [result] -> result
      [] -> save(socket, params, nil)
    end
  end

  defp save(%{assigns: %{editing: nil}} = socket, params, receipt) do
    %{current_scope: scope, choices: choices} = socket.assigns
    Portfolios.book_transaction(scope, choices, params, receipt)
  end

  defp save(socket, params, receipt) do
    %{current_scope: scope, choices: choices, editing: transaction} = socket.assigns
    Portfolios.update_transaction(scope, choices, transaction, params, receipt)
  end

  # A booking or a change, with or without a receipt, may change the checks of the inbox.
  defp recheck_inbox({:ok, _transaction_or_transactions} = result, socket) do
    Receipts.recheck(socket.assigns.current_scope)
    result
  end

  defp recheck_inbox(result, _socket), do: result

  defp saved({:ok, [_dividend, _removal]}, socket),
    do: done(socket, "Dividende und Entnahme gebucht.")

  defp saved({:ok, _transaction_or_transactions}, socket),
    do: done(socket, "Buchung gespeichert.")

  defp saved({:error, :read_only}, socket), do: {:noreply, close(socket)}
  defp saved({:error, :gone}, socket), do: done(socket, "Diese Buchung gibt es nicht mehr.")

  defp saved({:error, message}, socket) when is_binary(message),
    do: {:noreply, assign(socket, :error, message)}

  defp saved({:error, changeset}, socket), do: {:noreply, put_form(socket, changeset)}

  defp done(socket, message) do
    MarketData.broadcast()
    send(self(), {__MODULE__, :done, message})
    {:noreply, assign(socket, open: false, editing: nil, receipt: nil, new_security: nil)}
  end

  # A security created from the receipt passes its check.
  defp recheck_receipt(%{assigns: %{receipt: %{} = receipt}} = socket) do
    case Receipts.get_ready_receipt(socket.assigns.current_scope, receipt.id) do
      nil -> socket
      fresh -> assign(socket, :receipt, fresh)
    end
  end

  defp recheck_receipt(socket), do: socket

  defp close(socket) do
    socket =
      Enum.reduce(socket.assigns.uploads.receipt.entries, socket, fn entry, socket ->
        cancel_upload(socket, :receipt, entry.ref)
      end)

    assign(socket, open: false, editing: nil, receipt: nil, new_security: nil)
  end

  # A receipt whose depot number names no portfolio marks the select until one is picked.
  defp put_form(socket, changeset) do
    depot_number_warning =
      socket.assigns.receipt && Ecto.Changeset.get_field(changeset, :portfolio_id) == nil &&
        ReceiptComponents.depot_number_warning(socket.assigns.receipt)

    socket
    |> assign(:kind, Ecto.Changeset.get_field(changeset, :kind))
    |> assign(:form, to_form(changeset, as: :transaction))
    |> assign(:depot_number_warning, depot_number_warning || nil)
  end
end
