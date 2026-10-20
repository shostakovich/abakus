defmodule AbakusWeb.ImportSync do
  @moduledoc """
  Import & Sync in Finanzen: its title and tabs, Bankdateien and Bankverbindungen for the budget owner and Belege for
  users with a portfolio, with the count of the inbox; and the counts an import shows.
  """
  use Phoenix.Component
  use AbakusWeb, :verified_routes

  import Setzkasten.Components.Feedback, only: [badge: 1]
  import Setzkasten.Components.Layout, only: [header: 1]
  import Setzkasten.Components.Navigation, only: [tabs: 1]

  alias Abakus.Format
  alias AbakusWeb.Areas

  attr :tab, :atom, required: true, values: [:files, :bank_connections, :receipts]
  attr :current_scope, :map, required: true
  attr :inbox, :integer, default: 0, doc: "the recognised receipts in the inbox"
  slot :subtitle
  slot :actions

  @doc "The title with the tabs; each tab lives in its own live_session, so they load the page."
  def import_header(assigns) do
    assigns = assign(assigns, :tabs, shown_tabs(assigns.current_scope))

    ~H"""
    <.header>
      Import &amp; Sync
      <:subtitle :if={@subtitle != []}>{render_slot(@subtitle)}</:subtitle>
      <:actions :if={@actions != []}>{render_slot(@actions)}</:actions>
    </.header>
    <.tabs id="import-tabs" label="Import & Sync" class="mb-6">
      <:tab :for={{tab, label, path} <- @tabs} href={path} active={tab == @tab}>
        {label}
        <.badge :if={tab == :receipts and @inbox > 0} id="inbox-count" style={:plain}>
          {@inbox}<span class="sr-only"> im Eingang</span>
        </.badge>
      </:tab>
    </.tabs>
    """
  end

  @doc "The count of new transactions an import brings."
  def new_label(count), do: "#{Format.number(count)} neu"

  @doc "The count of transactions an import proposes as matches of existing ones."
  def matched_label(1), do: "1 Zuordnungsvorschlag"
  def matched_label(count), do: "#{Format.number(count)} Zuordnungsvorschläge"

  defp shown_tabs(scope) do
    [
      Areas.allowed?(scope, :budget) && {:files, "Bankdateien", ~p"/budget/import"},
      Areas.allowed?(scope, :budget) &&
        {:bank_connections, "Bankverbindungen", ~p"/budget/bank-connections"},
      Areas.allowed?(scope, :depot) && {:receipts, "Belege", ~p"/depot/receipts"}
    ]
    |> Enum.filter(& &1)
  end
end
