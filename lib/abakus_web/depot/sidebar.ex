defmodule AbakusWeb.Depot.Sidebar do
  @moduledoc """
  The portfolios and accounts with their values that the sidebar lists on the Depot's pages. An
  `on_mount` hook assigns them as `@depot_sidebar` and loads them again when new prices arrive.

  The hook subscribes the page to the market data and refreshes stale quotes, so a LiveView that
  shows prices itself only handles `:market_data_updated`, which reaches it after the sidebar.

  It counts the recognised receipts in the inbox for the count on the tab „Buchungen“, as
  `@depot_sidebar.inbox`; a page that shows the inbox itself, i.e. assigns `:inbox`, also gets
  `:receipts_updated`.
  """
  use AbakusWeb, :verified_routes

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [attach_hook: 4, connected?: 1]

  alias Abakus.Depot.{MarketData, Portfolios, Receipts}
  alias Abakus.LocalTime

  def on_mount(:default, _params, _session, socket) do
    if connected?(socket) do
      MarketData.subscribe()
      MarketData.refresh_stale_quotes()
      Receipts.subscribe(socket.assigns.current_scope)
    end

    {:cont, socket |> load() |> attach_hook(:depot_sidebar, :handle_info, &reload/2)}
  end

  defp reload(:market_data_updated, socket), do: {:cont, load(socket)}

  defp reload(:receipts_updated, socket) do
    sidebar = %{socket.assigns.depot_sidebar | inbox: inbox_count(socket)}
    socket = assign(socket, :depot_sidebar, sidebar)
    if Map.has_key?(socket.assigns, :inbox), do: {:cont, socket}, else: {:halt, socket}
  end

  defp reload(_message, socket), do: {:cont, socket}

  defp load(socket) do
    sidebar = Portfolios.sidebar(socket.assigns.current_scope, LocalTime.today())
    assign(socket, :depot_sidebar, Map.put(sidebar, :inbox, inbox_count(socket)))
  end

  defp inbox_count(socket), do: Receipts.inbox_count(socket.assigns.current_scope)

  @doc "A portfolio opens its holdings."
  def portfolio_path(portfolio), do: ~p"/depot/holdings?#{[portfolio: portfolio.id]}"

  @doc """
  An account opens the holdings of the portfolio it belongs to with its row marked, an account of
  no portfolio all holdings.
  """
  def account_path(nil, account), do: ~p"/depot/holdings?#{[account: account.id]}"

  def account_path(portfolio, account),
    do: ~p"/depot/holdings?#{[portfolio: portfolio.id, account: account.id]}"
end
