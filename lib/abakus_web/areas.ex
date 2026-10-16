defmodule AbakusWeb.Areas do
  @moduledoc """
  The app's areas, Finanzen and Kasse (ADR 0017), each with its own sidebar and dock on phones.

  Access is checked per part: the budget's pages (`/budget`) are its owner's (ADR 0007), the Kasse's (`/kasse`) its
  people's (ADR 0008), and the Depot's (`/depot`) everyone's in Finanzen, i.e. the budget owner and every user with
  a portfolio; anyone else gets 404 on them. The area used last is kept in the session, so `/` opens it.
  """
  use AbakusWeb, :verified_routes

  import Plug.Conn

  alias Abakus.Users.Scope
  alias AbakusWeb.NotFoundError

  @doc "The areas the scope's user may use, in sidebar order, each with the path of its first page."
  def for_scope(%Scope{} = scope) do
    [
      allowed?(scope, :finanzen) &&
        %{key: :finanzen, label: "Finanzen", icon: "wallet", path: finanzen_path(scope)},
      allowed?(scope, :kasse) && %{key: :kasse, label: "Kasse", icon: "receipt", path: ~p"/kasse"}
    ]
    |> Enum.filter(& &1)
  end

  def for_scope(nil), do: []

  defp finanzen_path(scope), do: if(allowed?(scope, :budget), do: ~p"/budget", else: ~p"/depot")

  @doc """
  Whether the scope's user may use a part: `:budget`, `:kasse`, `:depot` (has a portfolio) or `:finanzen` (the
  budget or a portfolio, which opens the Depot's pages).
  """
  def allowed?(nil, _part), do: false
  def allowed?(%Scope{} = scope, :budget), do: scope.user.budget_owner
  def allowed?(%Scope{} = scope, :kasse), do: scope.participant != nil
  def allowed?(%Scope{} = scope, :depot), do: scope.depot
  def allowed?(%Scope{} = scope, :finanzen), do: scope.user.budget_owner or scope.depot

  @doc "Where `/` leads: the area used last if the user may still use it, else their first one, else the settings."
  def home_path(scope, last_area) do
    case shown_area(for_scope(scope), last_area) do
      nil -> ~p"/settings"
      area -> area.path
    end
  end

  @doc "Plug for a part's pages: 404 unless the user may use it; otherwise the session remembers its area."
  def require_area(conn, part) do
    ensure_allowed!(conn.assigns.current_scope, part)
    put_session(conn, :area, Atom.to_string(area_of(part)))
  end

  @doc """
  `on_mount`: `{:require, part}` for a part's pages, which answer 404 unless the user may use it;
  `:assign` for pages outside the areas, which show the area used last. Both assign `areas` (those the user may
  use) and `area` (the current one's key, or `nil`).
  """
  def on_mount({:require, part}, _params, _session, socket) do
    scope = socket.assigns.current_scope
    ensure_allowed!(scope, part)
    {:cont, Phoenix.Component.assign(socket, areas: for_scope(scope), area: area_of(part))}
  end

  def on_mount(:assign, _params, session, socket) do
    areas = for_scope(socket.assigns.current_scope)
    area = shown_area(areas, session["area"])
    {:cont, Phoenix.Component.assign(socket, areas: areas, area: area && area.key)}
  end

  @doc "Shows the Depot in Finanzen, and Finanzen itself, as soon as the user's first portfolio exists."
  def open_depot(%{assigns: %{current_scope: %Scope{depot: true}}} = socket), do: socket

  def open_depot(socket) do
    scope = %{socket.assigns.current_scope | depot: true}

    Phoenix.Component.assign(socket,
      current_scope: scope,
      areas: for_scope(scope),
      area: socket.assigns.area || :finanzen
    )
  end

  @doc "Hides the Depot again once the user's last portfolio is gone, e.g. after a PP import deleted it."
  def close_depot(%{assigns: %{current_scope: %Scope{depot: false}}} = socket), do: socket

  def close_depot(socket) do
    scope = %{socket.assigns.current_scope | depot: false}
    areas = for_scope(scope)
    area = shown_area(areas, socket.assigns.area && Atom.to_string(socket.assigns.area))

    Phoenix.Component.assign(socket, current_scope: scope, areas: areas, area: area && area.key)
  end

  defp area_of(:kasse), do: :kasse
  defp area_of(part) when part in [:budget, :depot, :finanzen], do: :finanzen

  defp shown_area(areas, last_area),
    do: Enum.find(areas, &(Atom.to_string(&1.key) == last_area)) || List.first(areas)

  defp ensure_allowed!(scope, part), do: allowed?(scope, part) || raise(NotFoundError)
end
