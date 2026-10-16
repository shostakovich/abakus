defmodule AbakusWeb.Depot.ReceiptComponents do
  @moduledoc """
  How the screens show a receipt of the inbox: its row on „Buchungen“, and in the dialog „Beleg
  prüfen“ its checks and its text with the recognised values marked.
  """
  use Phoenix.Component
  use AbakusWeb, :verified_routes
  use Setzkasten

  alias Abakus.Depot.Portfolios.Receipt
  alias Abakus.Depot.Receipts.{Check, Checks, Correction, Fields}
  alias AbakusWeb.Depot.{Format, ReceiptText, TransactionDialog}

  @kinds %{purchase: "Kauf", sale: "Verkauf", dividend: "Dividende"}

  attr :receipts, :list, required: true
  attr :names, :map, required: true, doc: "the names of the known securities by ISIN"
  attr :polled_at, DateTime, default: nil, doc: "when the user's Paperless was polled last"

  @doc "The inbox: a row per receipt with what it needs next."
  def inbox(assigns) do
    ~H"""
    <section id="inbox" aria-labelledby="inbox-title">
      <.section_heading id="inbox-title" count={length(@receipts)}>
        Eingang
        <:actions>
          <span :if={@polled_at} id="inbox-polled" class="text-sm text-base-content/70">
            zuletzt abgefragt {Format.recent(@polled_at)}
          </span>
        </:actions>
      </.section_heading>
      <.list>
        <.inbox_row :for={receipt <- @receipts} receipt={receipt} names={@names} />
      </.list>
    </section>
    """
  end

  attr :receipt, Receipt, required: true
  attr :names, :map, required: true

  defp inbox_row(assigns) do
    assigns = assign(assigns, state: state(assigns.receipt))

    ~H"""
    <.list_row id={"receipt-#{@receipt.id}"} title={title(@receipt, @names)} data-state={@state}>
      <:leading>
        <.avatar icon={state_icon(@state)} loading={@state == :recognising} />
      </:leading>
      <:meta>
        <span class="flex flex-wrap items-center gap-x-2 whitespace-normal">
          <.badge id={"receipt-#{@receipt.id}-status"} tone={status_tone(@state)}>
            {status(@state)}
          </.badge>
          <span class="min-w-0">{detail(@receipt, @state)}</span>
        </span>
        <span
          :if={@state == :warning}
          id={"receipt-#{@receipt.id}-warning"}
          class="block whitespace-normal text-base-content"
        >
          {warning(@receipt)}
        </span>
      </:meta>
      <:trailing :if={@state != :recognising}>
        <.inbox_action receipt={@receipt} state={@state} />
      </:trailing>
    </.list_row>
    """
  end

  attr :receipt, Receipt, required: true
  attr :state, :atom, required: true

  # Discarding is no delete: uploading the PDF again brings it back.
  defp inbox_action(%{state: state} = assigns) when state in [:unsupported, :duplicate] do
    ~H"""
    <.button
      size={:sm}
      phx-click="discard"
      phx-value-id={@receipt.id}
      aria-label={"#{@receipt.filename} verwerfen"}
    >
      Verwerfen
    </.button>
    """
  end

  defp inbox_action(assigns) do
    ~H"""
    <.button size={:sm} phx-click={TransactionDialog.open_receipt(@receipt.id)}>
      {action_label(@state, @receipt)}
    </.button>
    """
  end

  # What a receipt needs next: wait, discard, book as recognised, check a warning, or type it.
  defp state(%Receipt{status: :recognising}), do: :recognising
  defp state(%Receipt{status: :unsupported}), do: :unsupported
  defp state(%Receipt{fields: nil}), do: :unrecognised

  defp state(%Receipt{checks: checks}) do
    cond do
      Checks.duplicate?(checks) -> :duplicate
      problems(checks) != [] -> :warning
      true -> :passed
    end
  end

  # A missing reference is no problem: not every bank prints one.
  defp problems(checks) do
    Enum.reject(
      checks,
      &(&1.result == :passed or (&1.name == :reference and &1.result == :missing))
    )
  end

  defp status(:recognising), do: "Wird erkannt"
  defp status(:unsupported), do: "Nicht unterstützt"
  defp status(:unrecognised), do: "Nicht erkannt"
  defp status(:duplicate), do: "Doppelt"
  defp status(:warning), do: "Bitte prüfen"
  defp status(:passed), do: "Geprüft"

  defp status_tone(:passed), do: :success
  defp status_tone(state) when state in [:unrecognised, :duplicate, :warning], do: :warning
  defp status_tone(_state), do: :neutral

  defp state_icon(:passed), do: "check"
  defp state_icon(:warning), do: "triangle-alert"
  defp state_icon(:duplicate), do: "copy"
  defp state_icon(:unsupported), do: "file-text"
  defp state_icon(:unrecognised), do: "file-text"
  defp state_icon(:recognising), do: "file-text"

  defp action_label(:unrecognised, _receipt), do: "Erfassen"

  defp action_label(:warning, receipt) do
    if Enum.any?(receipt.checks, &(&1.name in [:amount, :found] and &1.result == :failed)),
      do: "Korrigieren",
      else: "Prüfen und buchen"
  end

  defp action_label(_state, _receipt), do: "Prüfen und buchen"

  defp title(%Receipt{fields: %Fields{kind: kind} = fields}, names) when is_map_key(@kinds, kind),
    do: join_meta([@kinds[kind], names[fields.isin] || fields.security_name])

  defp title(receipt, _names), do: receipt.filename

  defp detail(receipt, :recognising), do: source(receipt)
  defp detail(receipt, :unsupported), do: source(receipt)
  defp detail(receipt, :unrecognised), do: join_meta([source(receipt), "bitte von Hand erfassen"])

  defp detail(receipt, :duplicate) do
    check = Enum.find(receipt.checks, &(&1.name == :reference))

    join_meta([
      date(receipt.fields),
      source(receipt),
      "gleiche Referenznummer wie die Buchung vom #{Format.date(check.booked_on)}"
    ])
  end

  defp detail(receipt, :warning), do: join_meta(figures(receipt.fields) ++ [source(receipt)])

  defp detail(receipt, :passed), do: join_meta(figures(receipt.fields) ++ [source(receipt)])

  defp source(%Receipt{paperless_id: nil}), do: "Upload"
  defp source(%Receipt{paperless_id: id}), do: "Paperless ##{id}"

  defp figures(fields) do
    [
      date(fields),
      fields.shares && "#{Format.rate(fields.shares)} Stück",
      fields.amount && "#{Format.decimal(fields.amount, 2)} €"
    ]
  end

  defp warning(receipt), do: receipt.checks |> problems() |> hd() |> check_text(receipt.fields)

  defp date(%Fields{date: date}), do: date && Format.date(date)

  @doc "What the dialog says the receipt is: its Paperless document or file, kind and date."
  def receipt_subtitle(%Receipt{fields: fields} = receipt) do
    kind =
      case fields do
        %Fields{kind: kind, date: %Date{} = date} when is_map_key(@kinds, kind) ->
          "#{@kinds[kind]} vom #{Format.date(date)}"

        _unknown ->
          nil
      end

    join_meta([if(receipt.paperless_id, do: source(receipt), else: receipt.filename), kind])
  end

  attr :receipt, Receipt, required: true

  @doc "The receipt's text as on paper, with the recognised values marked, and its PDF."
  def sheet(assigns) do
    assigns =
      assign(assigns, :pieces, ReceiptText.pieces(assigns.receipt.text, assigns.receipt.fields))

    ~H"""
    <div class="mb-2 flex min-h-8 items-center justify-between gap-2">
      <h3 class="text-sm text-base-content/70">Text des Belegs</h3>
      <.button
        id="receipt-pdf"
        href={~p"/depot/receipts/#{@receipt.id}"}
        target="_blank"
        rel="noopener"
        variant={:ghost}
        size={:sm}
        icon="file-text"
      >
        PDF öffnen
      </.button>
    </div>
    <div :if={@pieces != []} class="rounded-box border border-base-content/10 bg-base-100 p-4">
      <pre
        id="receipt-text"
        class="app-receipt-lines"
        tabindex="0"
        aria-label="Text des Belegs"
      ><%= for piece <- @pieces do %><.piece piece={piece} /><% end %></pre>
    </div>
    <.alert :if={@pieces == []} id="receipt-text" tone={:neutral}>
      Das PDF hat keinen lesbaren Text. Bitte die Werte aus dem PDF übernehmen.
    </.alert>
    """
  end

  defp piece(%{piece: {:mark, _text}} = assigns), do: ~H"<mark>{elem(@piece, 1)}</mark>"
  defp piece(%{piece: {:text, _text}} = assigns), do: ~H"{elem(@piece, 1)}"

  attr :receipt, Receipt, required: true

  @doc "The receipt's checks, or why there are none."
  def checklist(%{receipt: %Receipt{fields: nil}} = assigns) do
    ~H"""
    <h3 class="mb-2 text-sm text-base-content/70">Prüfungen</h3>
    <.alert id="receipt-checks" tone={:warning} class="mb-4">
      Nicht erkannt. Bitte die Werte aus dem Beleg übernehmen.
    </.alert>
    """
  end

  def checklist(assigns) do
    ~H"""
    <h3 id="receipt-checks-title" class="mb-2 text-sm text-base-content/70">Prüfungen</h3>
    <.list
      id="receipt-checks"
      flush
      aria-labelledby="receipt-checks-title"
      class="mb-4 rounded-box border border-base-content/10 text-sm"
    >
      <li
        :for={check <- @receipt.checks}
        id={"receipt-check-#{check.name}"}
        class="list-row items-start gap-3 py-2"
        data-problem={check_problem?(check)}
      >
        <.icon name={check_icon(check)} class={["mt-0.5 shrink-0", check_tone(check)]} />
        <p class="list-col-grow">
          <span class="sr-only">{check_result(check)}: </span>{check_text(check, @receipt.fields)}
        </p>
      </li>
    </.list>
    """
  end

  @doc "What the price field says when the receipt's amount does not add up, nil otherwise."
  def price_warning(%Receipt{checks: checks, fields: fields}) do
    if Enum.any?(checks, &match?(%Check{name: :amount, result: :failed}, &1)),
      do: "Summe laut Beleg: #{Format.decimal(fields.amount, 2)}\u00A0€"
  end

  def price_warning(nil), do: nil

  @doc "What the portfolio field says when the receipt's depot number names none, nil otherwise."
  def depot_number_warning(%Receipt{checks: checks, fields: fields}) do
    case Enum.find(checks, &(&1.name == :depot)) do
      %Check{result: :failed} -> "Laut Beleg Depot #{Format.masked(fields.depot_number)}"
      %Check{result: :missing} -> "Der Beleg nennt keine Depotnummer."
      _passed_or_none -> nil
    end
  end

  defp check_problem?(check), do: problems([check]) != []

  defp check_icon(%Check{result: :passed}), do: "circle-check"
  defp check_icon(%Check{name: :reference, result: :missing}), do: "info"
  defp check_icon(%Check{name: :reference, result: :failed}), do: "circle-alert"
  defp check_icon(_check), do: "triangle-alert"

  defp check_tone(%Check{result: :passed}), do: "text-success-ink"
  defp check_tone(%Check{name: :reference, result: :missing}), do: "text-base-content/70"
  defp check_tone(%Check{name: :reference, result: :failed}), do: "text-error-ink"
  defp check_tone(_check), do: nil

  defp check_result(%Check{result: :passed}), do: "bestanden"
  defp check_result(%Check{name: :reference, result: :missing}), do: "Hinweis"
  defp check_result(_check), do: "nicht bestanden"

  defp check_text(%Check{name: :amount, result: :passed} = check, fields),
    do: "#{Checks.formula(fields)} = #{Format.decimal(check.computed, 2)} €"

  defp check_text(%Check{name: :amount, result: :failed} = check, fields) do
    text =
      "#{Checks.formula(fields)} ergibt #{Format.decimal(check.computed, 2)} €, " <>
        "der Beleg nennt #{Format.decimal(fields.amount, 2)} €."

    text <> " Bitte Kurs prüfen."
  end

  defp check_text(%Check{name: :amount, result: :missing}, _fields),
    do: "Betrag nicht prüfbar: Stück, Kurs oder Betrag fehlen."

  defp check_text(%Check{name: :found, result: :passed}, _fields),
    do: "Alle Werte im Beleg gefunden"

  defp check_text(%Check{name: :found, result: :failed} = check, fields),
    do: Correction.not_found(check, fields) <> ", bitte prüfen."

  defp check_text(%Check{name: :isin, result: :passed}, _fields),
    do: "ISIN gültig und bekannt"

  defp check_text(%Check{name: :isin, result: :new_security}, fields),
    do: "ISIN #{fields.isin} gültig, Wertpapier noch nicht angelegt"

  defp check_text(%Check{name: :isin, result: :failed}, fields),
    do: "ISIN #{fields.isin} ist ungültig, bitte prüfen."

  defp check_text(%Check{name: :isin, result: :missing}, _fields),
    do: "Keine ISIN erkannt"

  defp check_text(%Check{name: :depot, result: :passed} = check, fields),
    do:
      "Depot #{Format.masked(fields.depot_number)} gehört zu „#{Format.portfolio_name(check.portfolio_name)}“"

  defp check_text(%Check{name: :depot, result: :failed}, fields),
    do:
      "Depot #{Format.masked(fields.depot_number)} gehört zu keinem deiner Depots. " <>
        "Bitte Depot wählen."

  defp check_text(%Check{name: :depot, result: :missing}, _fields),
    do: "Keine Depotnummer erkannt. Bitte Depot wählen."

  defp check_text(%Check{name: :reference, result: :passed}, fields),
    do: "Referenz #{fields.bank_reference} noch nicht gebucht"

  defp check_text(%Check{name: :reference, result: :failed} = check, _fields),
    do: "Gleiche Referenznummer wie die Buchung vom #{Format.date(check.booked_on)}"

  defp check_text(%Check{name: :reference, result: :missing}, _fields),
    do: "Keine Referenznummer erkannt"
end
