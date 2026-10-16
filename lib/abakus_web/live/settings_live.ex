defmodule AbakusWeb.SettingsLive do
  @moduledoc """
  The settings' sections of their own: Aussehen (the theme, per device) and, for the budget owner, the YNAB import's
  status, read from the data. Zugang is `AbakusWeb.UserLive.Settings`, behind the sudo plug.
  """
  use AbakusWeb, :live_view

  alias Abakus.{Format, YnabImport}
  alias AbakusWeb.Areas

  @titles %{appearance: "Aussehen", ynab_import: "YNAB-Import"}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.settings
      current={@section}
      flash={@flash}
      current_scope={@current_scope}
      areas={@areas}
      area={@area}
      groups={@settings_groups}
    >
      <.header>{@page_title}</.header>
      <.appearance :if={@section == :appearance} />
      <.ynab_import :if={@section == :ynab_import} status={@ynab_status} />
    </Layouts.settings>
    """
  end

  defp appearance(assigns) do
    ~H"""
    <section id="appearance">
      <p class="mb-3 text-sm text-base-content/70">Gilt für dieses Gerät.</p>
      <.theme_toggle />
      <p class="mt-6 max-w-prose text-sm text-base-content/70">
        Als App installieren: im Browser „Zum Home-Bildschirm“ wählen.
      </p>
    </section>
    """
  end

  attr :status, YnabImport.Status

  defp ynab_import(assigns) do
    ~H"""
    <section id="ynab-import" class="flex flex-col gap-3">
      <p class="max-w-prose text-sm text-base-content/70">
        Ein neuer Import ersetzt das ganze Budget. Sobald Abakus eigene Buchungen hat, läuft er nicht mehr.
      </p>
      <.empty_state :if={!@status} plush="history" icon="history">
        Noch nichts aus YNAB übernommen.
      </.empty_state>
      <div :if={@status} class="flex flex-wrap items-center gap-2">
        <.badge tone={:success}>abgeschlossen</.badge>
        <span class="text-sm text-base-content/70">
          übernommen am {Format.date(@status.imported_at)}
        </span>
      </div>
      <p :if={@status} id="ynab-import-summary" class="max-w-prose">
        Aus YNAB übernommen: {summary(@status)}.
      </p>
    </section>
    """
  end

  defp summary(status) do
    [
      counted(status.accounts, "Konto", "Konten"),
      counted(status.category_groups, "Kategoriegruppe", "Kategoriegruppen") <>
        " mit " <> counted(status.categories, "Kategorie", "Kategorien"),
      counted(status.payees, "Empfänger", "Empfänger"),
      counted(status.transactions, "Buchung", "Buchungen"),
      status.first_month && "Budget ab #{Format.month_year(status.first_month)}"
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(", ")
  end

  defp counted(1, one, _many), do: "1 #{one}"
  defp counted(number, _one, many), do: "#{Format.number(number)} #{many}"

  @impl true
  def mount(_params, _session, socket), do: {:ok, socket}

  @impl true
  def handle_params(_params, _url, socket) do
    section = socket.assigns.live_action
    if section == :ynab_import, do: ensure_budget!(socket.assigns.current_scope)

    {:noreply,
     socket
     |> assign(:section, section)
     |> assign(:page_title, @titles[section])
     |> assign(:ynab_status, if(section == :ynab_import, do: YnabImport.status()))}
  end

  defp ensure_budget!(scope),
    do: Areas.allowed?(scope, :budget) || raise(AbakusWeb.NotFoundError)
end
