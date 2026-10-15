defmodule AbakusWeb.PageController do
  use AbakusWeb, :controller

  alias AbakusWeb.Areas

  @doc "Opens the area used last."
  def home(conn, _params) do
    redirect(conn, to: Areas.home_path(conn.assigns.current_scope, get_session(conn, :area)))
  end
end
