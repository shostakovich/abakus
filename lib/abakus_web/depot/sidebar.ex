defmodule AbakusWeb.Depot.Sidebar do
  @moduledoc """
  The portfolios with their values that the sidebar lists in Finanzen. An `on_mount` hook assigns
  them as `@depot_sidebar` and loads them again when new prices arrive.

  The hook subscribes the page to the market data and refreshes stale quotes. On the Depot's pages
  (`:default`) `:market_data_updated` reaches the LiveView after the sidebar, so one that shows
  prices itself only handles it; on the budget's pages (`:budget`) it stops at the sidebar.

  It counts the recognised receipts in the inbox for Import & Sync, as `@depot_sidebar.inbox`; a page that shows
  the inbox itself, i.e. assigns `:inbox`, also gets `:receipts_updated`.
  """
  use AbakusWeb, :verified_routes

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [attach_hook: 4, connected?: 1]

  alias Abakus.Depot.{MarketData, Portfolios, Receipts}
  alias Abakus.LocalTime

  def on_mount(:default, _params, _session, socket), do: {:cont, attach(socket, :cont)}
  def on_mount(:budget, _params, _session, socket), do: {:cont, attach(socket, :halt)}

  defp attach(socket, prices) do
    if connected?(socket) do
      MarketData.subscribe()
      MarketData.refresh_stale_quotes()
      Receipts.subscribe(socket.assigns.current_scope)
    end

    socket
    |> load()
    |> attach_hook(:depot_sidebar, :handle_info, &reload(&1, &2, prices))
  end

  defp reload(:market_data_updated, socket, prices), do: {prices, load(socket)}

  defp reload(:receipts_updated, socket, _prices) do
    sidebar = %{socket.assigns.depot_sidebar | inbox: inbox_count(socket)}
    socket = assign(socket, :depot_sidebar, sidebar)
    if Map.has_key?(socket.assigns, :inbox), do: {:cont, socket}, else: {:halt, socket}
  end

  defp reload(_message, socket, _prices), do: {:cont, socket}

  defp load(socket) do
    sidebar = Portfolios.sidebar(socket.assigns.current_scope, LocalTime.today())
    assign(socket, :depot_sidebar, Map.put(sidebar, :inbox, inbox_count(socket)))
  end

  defp inbox_count(socket), do: Receipts.inbox_count(socket.assigns.current_scope)

  @doc "A portfolio opens its holdings."
  def portfolio_path(portfolio), do: ~p"/depot/holdings?#{[portfolio: portfolio.id]}"
end
