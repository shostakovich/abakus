defmodule AbakusWeb.Bookkeeping.InvoiceController do
  @moduledoc """
  Downloads the PDF of one of the signed-in user's invoices: a ZUGFeRD e-invoice, or for one from Lexoffice its
  original from Paperless.
  """
  use AbakusWeb, :controller

  alias Abakus.Bookkeeping.{Attachments, Invoice, InvoicePdf, Invoices}

  def show(conn, %{"id" => id}) do
    scope = conn.assigns.current_scope

    with %{} = invoice <- Invoices.get_invoice(scope, id),
         {:ok, pdf} <- pdf(scope, invoice) do
      send_download(conn, {:binary, pdf},
        filename: InvoicePdf.filename(invoice),
        content_type: "application/pdf"
      )
    else
      nil ->
        conn |> put_status(:not_found) |> text("Rechnung nicht gefunden")

      {:error, _reason} ->
        conn
        |> put_status(:bad_gateway)
        |> text("Die Rechnung liegt in Paperless, das gerade nicht erreichbar ist.")

      :error ->
        conn
        |> put_status(:internal_server_error)
        |> text("Die Rechnung ließ sich nicht erstellen.")
    end
  end

  defp pdf(scope, %Invoice{} = invoice) do
    if Invoice.imported?(invoice),
      do: Attachments.download(scope, invoice.paperless_id),
      else: InvoicePdf.render(invoice)
  end
end
