defmodule AbakusWeb.Depot.Sidebar do
  @moduledoc """
  The portfolios with their values that the sidebar lists in Finanzen. An `on_mount` hook assigns
  them as `@depot_sidebar` and loads them again when new prices arrive or a booking was saved, the budget's
  accounts in `@account_groups` too.

  The hook subscribes the page to the market data and the exchange rates and refreshes stale
  quotes. On the Depot's pages (`:default`) `:market_data_updated` reaches the LiveView after the
  sidebar, so one that shows prices itself only handles it; on the budget's pages (`:budget`) it
  stops at the sidebar. `:exchange_rates_updated` comes back as `:market_data_updated`, as new
  rates change values as new prices do.

  It counts the recognised receipts in the inbox for Import & Sync, as `@depot_sidebar.inbox`; a page that shows
  the inbox itself, i.e. assigns `:inbox`, also gets `:receipts_updated`.
  """
  use AbakusWeb, :verified_routes

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [attach_hook: 4, connected?: 1]

  alias Abakus.Depot.{MarketData, Portfolios, Receipts}
  alias Abakus.{ExchangeRates, LocalTime}
  alias AbakusWeb.{AccountGroups, Areas}

  def on_mount(:default, _params, _session, socket), do: {:cont, attach(socket, :cont)}
  def on_mount(:budget, _params, _session, socket), do: {:cont, attach(socket, :halt)}

  defp attach(socket, prices) do
    if connected?(socket) do
      MarketData.subscribe()
      ExchangeRates.subscribe()
      MarketData.refresh_stale_quotes()
      Receipts.subscribe(socket.assigns.current_scope)
    end

    socket
    |> load()
    |> attach_hook(:depot_sidebar, :handle_info, &reload(&1, &2, prices))
  end

  defp reload(:market_data_updated, socket, prices),
    do: {prices, socket |> load() |> reload_account_groups()}

  defp reload(:exchange_rates_updated, socket, _prices) do
    send(self(), :market_data_updated)
    {:halt, socket}
  end

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

  defp reload_account_groups(%{assigns: %{account_groups: _groups}} = socket) do
    if Areas.allowed?(socket.assigns.current_scope, :budget),
      do: assign(socket, :account_groups, AccountGroups.load(socket.assigns.current_scope)),
      else: socket
  end

  defp reload_account_groups(socket), do: socket

  defp inbox_count(socket), do: Receipts.inbox_count(socket.assigns.current_scope)
end
