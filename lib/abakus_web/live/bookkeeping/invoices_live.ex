defmodule AbakusWeb.Bookkeeping.InvoicesLive do
  @moduledoc """
  The Buchhaltung's „Rechnungen“: the invoices the user wrote, the latest number first, each with its PDF to
  download; „Neue Rechnung“ writes the next one (`AbakusWeb.Bookkeeping.InvoiceFormLive`).
  """
  use AbakusWeb, :live_view

  alias Abakus.Bookkeeping.Invoices
  alias Abakus.Format

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
        >
          <:meta>
            {join_meta([
              Format.date(invoice.date),
              "Leistung #{Format.date_span(invoice.service_from, invoice.service_to)}",
              "fällig #{Format.date(invoice.due_date)}"
            ])}
          </:meta>
          <:trailing><.amount value={invoice.total} /></:trailing>
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

  @impl true
  def mount(_params, _session, socket) do
    invoices = Invoices.list_invoices(socket.assigns.current_scope)
    {:ok, assign(socket, page_title: "Rechnungen", invoices: invoices)}
  end
end
