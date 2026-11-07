defmodule AbakusWeb.Bookkeeping.FilingController do
  @moduledoc "Downloads ELSTER's transmission protocol of one of the signed-in user's sent returns."
  use AbakusWeb, :controller

  alias Abakus.Bookkeeping.Filings

  def protocol(conn, %{"id" => id}) do
    case Filings.get(conn.assigns.current_scope, id) do
      %{protocol: pdf} = filing when is_binary(pdf) ->
        send_download(conn, {:binary, pdf},
          filename: Filings.protocol_filename(filing),
          content_type: "application/pdf"
        )

      _none ->
        conn |> put_status(:not_found) |> text("Protokoll nicht gefunden")
    end
  end
end
