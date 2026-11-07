defmodule AbakusWeb.Bookkeeping.PaperlessController do
  @moduledoc """
  Shows a document of the signed-in user's Paperless in the browser, such as an attachment: only a PDF or an image, its
  type told by its first bytes. A document Paperless does not have is 404, Paperless failing or sending anything
  else 502.
  """
  use AbakusWeb, :controller

  alias Abakus.Bookkeeping.Attachments

  def show(conn, %{"id" => id}) do
    with {id, ""} when id > 0 <- Integer.parse(id),
         {:ok, content} <- Attachments.download(conn.assigns.current_scope, id),
         {:ok, type, extension} <- type(content) do
      conn
      |> put_resp_header("cache-control", "private, max-age=3600")
      |> send_download({:binary, content},
        filename: "Paperless #{id}.#{extension}",
        content_type: type,
        disposition: :inline
      )
    else
      {:error, {:http_status, 404}} -> missing(conn, "Beleg nicht gefunden")
      {:error, :not_connected} -> missing(conn, "Paperless ist nicht verbunden.")
      {:error, :type} -> failed(conn, "Paperless hat keine PDF- oder Bilddatei geliefert.")
      {:error, _reason} -> failed(conn, "Paperless ist gerade nicht erreichbar.")
      _invalid_id -> missing(conn, "Beleg nicht gefunden")
    end
  end

  defp type(<<"%PDF-", _rest::binary>>), do: {:ok, "application/pdf", "pdf"}
  defp type(<<0x89, "PNG\r\n", 0x1A, "\n", _rest::binary>>), do: {:ok, "image/png", "png"}
  defp type(<<0xFF, 0xD8, 0xFF, _rest::binary>>), do: {:ok, "image/jpeg", "jpg"}
  defp type(<<"II*", 0, _rest::binary>>), do: {:ok, "image/tiff", "tif"}
  defp type(<<"MM", 0, "*", _rest::binary>>), do: {:ok, "image/tiff", "tif"}

  defp type(<<"RIFF", _size::binary-size(4), "WEBP", _rest::binary>>),
    do: {:ok, "image/webp", "webp"}

  defp type(_other), do: {:error, :type}

  defp missing(conn, message), do: conn |> put_status(:not_found) |> text(message)
  defp failed(conn, message), do: conn |> put_status(:bad_gateway) |> text(message)
end
