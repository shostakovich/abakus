defmodule AbakusWeb.Bookkeeping.InvoiceController do
  @moduledoc "Downloads the PDF of one of the signed-in user's invoices, a ZUGFeRD e-invoice."
  use AbakusWeb, :controller

  alias Abakus.Bookkeeping.{InvoicePdf, Invoices}

  def show(conn, %{"id" => id}) do
    with %{} = invoice <- Invoices.get_invoice(conn.assigns.current_scope, id),
         {:ok, pdf} <- InvoicePdf.render(invoice) do
      send_download(conn, {:binary, pdf},
        filename: InvoicePdf.filename(invoice),
        content_type: "application/pdf"
      )
    else
      nil ->
        conn |> put_status(:not_found) |> text("Rechnung nicht gefunden")

      :error ->
        conn
        |> put_status(:internal_server_error)
        |> text("Die Rechnung ließ sich nicht erstellen.")
    end
  end
end
