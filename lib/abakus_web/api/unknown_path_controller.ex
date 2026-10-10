defmodule AbakusWeb.Api.UnknownPathController do
  @moduledoc "Answers paths the API does not have, after the token check, as YNAB does."

  use AbakusWeb, :controller

  def show(conn, _params), do: AbakusWeb.Api.send_not_found(conn)
end
