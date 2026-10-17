defmodule AbakusWeb.PageController do
  use AbakusWeb, :controller

  alias AbakusWeb.Areas

  @doc "Opens the area used last."
  def home(conn, _params) do
    redirect(conn, to: Areas.home_path(conn.assigns.current_scope, get_session(conn, :area)))
  end

  @doc "The former account list's address opens the register of all accounts."
  def accounts(conn, _params), do: redirect(conn, to: ~p"/budget/accounts/all")

  @doc "Opens the settings at their first section that needs no recent sign-in."
  def settings(conn, _params), do: redirect(conn, to: ~p"/settings/appearance")
end
