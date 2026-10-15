defmodule AbakusWeb.Areas do
  @moduledoc """
  The app's areas, each with its own pages under its path, its section in the sidebar and its dock on phones. A
  user sees only the areas they may use: the Budget is its owner's (ADR 0007); anyone else gets 404 on its pages.
  The area used last is kept in the session, so `/` opens it.
  """
  use AbakusWeb, :verified_routes

  import Plug.Conn

  alias Abakus.Users.Scope

  defmodule NotFoundError do
    defexception message: "no such page", plug_status: 404
  end

  @doc "The areas the scope's user may use, in sidebar order."
  def for_scope(%Scope{user: user}), do: Enum.filter(all(), &may_use?(user, &1.key))
  def for_scope(nil), do: []

  defp all, do: [%{key: :budget, label: "Budget", icon: "wallet", path: ~p"/budget"}]

  defp may_use?(user, :budget), do: user.budget_owner

  @doc "Where `/` leads: the area used last if the user may still use it, else their first one, else the settings."
  def home_path(scope, last_area) do
    case shown_area(for_scope(scope), last_area) do
      nil -> ~p"/settings"
      area -> area.path
    end
  end

  @doc "Plug for an area's pages: 404 unless the user may use it; otherwise the session remembers it."
  def require_area(conn, key) do
    ensure_allowed!(conn.assigns.current_scope, key)
    put_session(conn, :area, Atom.to_string(key))
  end

  @doc """
  `on_mount`: `{:require, key}` for an area's pages, which answer 404 unless the user may use it;
  `:assign` for pages outside the areas, which show the area used last. Both assign `areas` (those the user may
  use) and `area` (the current one's key, or `nil`).
  """
  def on_mount({:require, key}, _params, _session, socket) do
    scope = socket.assigns.current_scope
    ensure_allowed!(scope, key)
    {:cont, Phoenix.Component.assign(socket, areas: for_scope(scope), area: key)}
  end

  def on_mount(:assign, _params, session, socket) do
    areas = for_scope(socket.assigns.current_scope)
    area = shown_area(areas, session["area"])
    {:cont, Phoenix.Component.assign(socket, areas: areas, area: area && area.key)}
  end

  @doc "Whether the scope's user may use the area."
  def allowed?(scope, key) when is_atom(key), do: Enum.any?(for_scope(scope), &(&1.key == key))

  defp shown_area(areas, last_area),
    do: Enum.find(areas, &(Atom.to_string(&1.key) == last_area)) || List.first(areas)

  defp ensure_allowed!(scope, key), do: allowed?(scope, key) || raise(NotFoundError)
end
