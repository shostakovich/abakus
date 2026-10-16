defmodule AbakusWeb.SettingsLive.Components do
  @moduledoc """
  The frame of the settings: the overview lists the sections; a section shows them as tabs from `lg` and below
  it a way back to the overview. The links load the page, since Zugang sits behind the sudo plug and the Depot's
  sections in the Depot's routes.
  """
  use AbakusWeb, :html

  @sections [
    {:access, "Zugang", "key-round", "Passkeys und E-Mail"},
    {:appearance, "Aussehen", "palette", "Hell, Dunkel oder System"},
    {:depots, "Depots", "briefcase", "Deine Depots und ihre Verrechnungskonten"},
    {:pp_import, "PP-Import", "upload", "Depots und Buchungen aus Portfolio Performance"},
    {:receipt_intake, "Belegeingang", "file-text", "Belege aus Paperless-ngx und ihre Erkennung"},
    {:ynab, "YNAB-Import", "history", "Was aus YNAB übernommen wurde"}
  ]

  attr :section, :atom, values: [nil | Enum.map(@sections, &elem(&1, 0))], required: true
  attr :flash, :map, required: true
  attr :current_scope, :map, required: true
  attr :areas, :list, required: true
  attr :area, :atom, required: true
  attr :account_groups, :list, required: true
  attr :account_dialog, :map, required: true
  slot :inner_block

  def page(assigns) do
    assigns = assign(assigns, :sections, sections(assigns.current_scope))

    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      current={:settings}
      areas={@areas}
      area={@area}
      width={:narrow}
      account_groups={@account_groups}
      account_dialog={@account_dialog}
    >
      <.header
        :if={@section}
        back_href={~p"/settings"}
        back_label="Einstellungen"
        class="lg:hidden"
      >
        {label(@section)}
      </.header>
      <.header class={@section && "max-lg:hidden"}>Einstellungen</.header>

      <.tabs :if={@section} id="settings-nav" label="Einstellungen" class="mb-6 max-lg:hidden">
        <:tab :for={{key, label, _icon, _hint} <- @sections} href={path(key)} active={key == @section}>
          {label}
        </:tab>
      </.tabs>

      <.list :if={!@section} id="settings-nav" aria-label="Einstellungen">
        <.list_row :for={{key, label, icon, hint} <- @sections} href={path(key)} title={label}>
          <:leading><.icon name={icon} class="size-5 text-base-content/70" /></:leading>
          <:meta>{hint}</:meta>
        </.list_row>
      </.list>

      {render_slot(@inner_block)}
    </Layouts.app>
    """
  end

  # YNAB-Import belongs to the Budget, Belegeingang to the Depot.
  defp sections(scope) do
    Enum.filter(@sections, fn {key, _label, _icon, _hint} -> shown?(key, scope) end)
  end

  defp shown?(:ynab, scope), do: AbakusWeb.Areas.allowed?(scope, :budget)
  defp shown?(:receipt_intake, scope), do: AbakusWeb.Areas.allowed?(scope, :depot)
  defp shown?(_key, _scope), do: true

  @doc "The section's name, e.g. for the page title."
  def label(section) do
    {^section, label, _icon, _hint} = List.keyfind(@sections, section, 0)
    label
  end

  defp path(:access), do: ~p"/settings/access"
  defp path(:appearance), do: ~p"/settings/appearance"
  defp path(:depots), do: ~p"/depot/portfolios"
  defp path(:pp_import), do: ~p"/depot/import"
  defp path(:receipt_intake), do: ~p"/depot/receipt-intake"
  defp path(:ynab), do: ~p"/settings/ynab"
end
