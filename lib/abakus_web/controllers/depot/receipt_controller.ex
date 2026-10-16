defmodule AbakusWeb.Depot.ReceiptController do
  @moduledoc "Shows the PDF of a receipt of the signed-in user in the browser."
  use AbakusWeb, :controller

  alias Abakus.Depot.Portfolios

  def show(conn, %{"id" => id}) do
    with {:ok, id} <- Abakus.Schema.cast_id(id),
         %{} = receipt <- Portfolios.get_receipt(conn.assigns.current_scope, id),
         file = Portfolios.receipt_file(receipt),
         true <- File.exists?(file) do
      conn
      |> put_resp_header("cache-control", "private, max-age=86400")
      |> send_download({:file, file},
        filename: receipt.filename,
        content_type: "application/pdf",
        disposition: :inline
      )
    else
      _missing -> conn |> put_status(:not_found) |> text("Beleg nicht gefunden")
    end
  end
end
