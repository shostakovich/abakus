defmodule AbakusWeb.Bookkeeping.InvoicesLive do
  @moduledoc """
  The Buchhaltung's „Rechnungen“: the invoices the user wrote, the latest number first, each with its PDF to
  download and whether it is paid; „Neue Rechnung“ writes the next one (`AbakusWeb.Bookkeeping.InvoiceFormLive`).
  An open invoice offers the incoming transactions proposed as its payment to confirm, a paid one to release its
  payment (`Abakus.Bookkeeping.InvoicePayments`).
  """
  use AbakusWeb, :live_view

  alias Abakus.Bookkeeping.{InvoicePayments, Invoices}
  alias Abakus.{Format, Money}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      areas={@areas}
      area={@area}
      current={:bookkeeping_invoices}
    >
      <.header>
        Rechnungen
        <:actions>
          <.button
            id="invoice-new"
            navigate={~p"/buchhaltung/invoices/new"}
            variant={:primary}
            icon="plus"
            class="max-md:hidden"
          >
            Neue Rechnung
          </.button>
        </:actions>
      </.header>
      <.list :if={@invoices != []} id="invoices">
        <.list_row
          :for={invoice <- @invoices}
          id={"invoice-#{invoice.id}"}
          title={"#{invoice.number} · #{invoice.recipient.name}"}
          href={pdf_path(invoice)}
          muted={Map.has_key?(@payments, invoice.id)}
        >
          <:meta>
            {join_meta([
              Format.date(invoice.date),
              "Leistung #{Format.date_span(invoice.service_from, invoice.service_to)}",
              status_text(invoice, @payments[invoice.id])
            ])}
          </:meta>
          <:trailing>
            <.badge :if={@proposals[invoice.id]} tone={:info}>Zahlung eingegangen</.badge>
            <.badge :if={!@payments[invoice.id] and !@proposals[invoice.id]}>offen</.badge>
            <.amount value={invoice.total} />
          </:trailing>
          <:action
            :for={payment <- Map.get(@proposals, invoice.id, [])}
            id={"invoice-#{invoice.id}-pay-#{payment.id}"}
            label={"Zahlung vom #{Format.date(payment.date)} bestätigen"}
            icon="circle-check"
            confirm="Zahlung bestätigen?"
            confirm_text={payment_text(payment)}
            confirm_label="Bestätigen"
            on_click={JS.push("confirm_payment", value: %{id: invoice.id, transaction: payment.id})}
          />
          <:action
            :if={@payments[invoice.id]}
            id={"invoice-#{invoice.id}-release"}
            label="Zahlung lösen"
            icon="unlink"
            confirm="Zahlung lösen?"
            confirm_text="Die Rechnung ist dann wieder offen; die Buchung bleibt, wie sie ist."
            confirm_label="Lösen"
            on_click={JS.push("release_payment", value: %{id: invoice.id})}
          />
          <:action
            id={"invoice-#{invoice.id}-download"}
            label="PDF herunterladen"
            icon="download"
            href={pdf_path(invoice)}
          />
        </.list_row>
      </.list>
      <.empty_state
        :if={@invoices == []}
        id="invoices-empty"
        layout={:page}
        plush="file-text"
        icon="file-text"
        title="Noch keine Rechnungen"
      >
        Eine Rechnung geht an einen Kunden, mit Positionen und Leistungszeitraum, und kommt als E-Rechnung
        (ZUGFeRD) zum Herunterladen.
      </.empty_state>
      <:fab><.fab navigate={~p"/buchhaltung/invoices/new"} label="Neue Rechnung" /></:fab>
    </Layouts.app>
    """
  end

  defp pdf_path(invoice), do: ~p"/buchhaltung/invoices/#{invoice.id}/pdf"

  defp status_text(_invoice, %{date: date}), do: "bezahlt am #{Format.date(date)}"
  defp status_text(invoice, nil), do: "fällig #{Format.date(invoice.due_date)}"

  defp payment_text(%{payee: %{name: name}} = payment),
    do: "#{name} hat am #{Format.date(payment.date)} #{Money.euros(payment.amount)} überwiesen."

  defp payment_text(payment),
    do: "Am #{Format.date(payment.date)} sind #{Money.euros(payment.amount)} eingegangen."

  @impl true
  def mount(_params, _session, socket),
    do: {:ok, socket |> assign(page_title: "Rechnungen") |> load()}

  @impl true
  def handle_event("confirm_payment", %{"id" => id, "transaction" => transaction_id}, socket) do
    scope = socket.assigns.current_scope

    message =
      with %{} = invoice <- Invoices.get_invoice(scope, id) do
        case InvoicePayments.confirm(scope, invoice, transaction_id) do
          {:ok, _payment} -> {:info, "Rechnung #{invoice.number} ist bezahlt."}
          {:error, :paid} -> {:error, "Rechnung #{invoice.number} ist schon bezahlt."}
          {:error, _reason} -> {:error, "Diese Zahlung passt nicht mehr zur Rechnung."}
        end
      end

    {:noreply, socket |> flash(message) |> load()}
  end

  def handle_event("release_payment", %{"id" => id}, socket) do
    scope = socket.assigns.current_scope

    message =
      with %{} = invoice <- Invoices.get_invoice(scope, id) do
        :ok = InvoicePayments.release(scope, invoice)
        {:info, "Rechnung #{invoice.number} ist wieder offen."}
      end

    {:noreply, socket |> flash(message) |> load()}
  end

  defp flash(socket, nil), do: put_flash(socket, :error, "Rechnung nicht gefunden.")
  defp flash(socket, {kind, message}), do: put_flash(socket, kind, message)

  defp load(socket) do
    scope = socket.assigns.current_scope
    invoices = Invoices.list_invoices(scope)

    assign(socket,
      invoices: invoices,
      payments: InvoicePayments.payments(scope, invoices),
      proposals: InvoicePayments.proposals(scope, invoices)
    )
  end
end
