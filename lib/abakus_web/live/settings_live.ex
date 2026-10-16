defmodule AbakusWeb.SettingsLive do
  @moduledoc """
  The settings' overview and the sections that need no recent sign-in: Aussehen (the theme, per device) and the
  YNAB import's status, read from the data. Zugang is `AbakusWeb.UserLive.Settings`, behind the sudo plug.
  """
  use AbakusWeb, :live_view

  alias Abakus.YnabImport
  alias AbakusWeb.{Areas, Format}
  alias AbakusWeb.SettingsLive.Components

  @impl true
  def render(assigns) do
    ~H"""
    <Components.page
      section={@section}
      flash={@flash}
      current_scope={@current_scope}
      areas={@areas}
      area={@area}
      account_groups={@account_groups}
      account_dialog={@account_dialog}
    >
      <.appearance :if={@section == :appearance} />
      <.ynab_import :if={@section == :ynab} status={@ynab_status} />
    </Components.page>
    """
  end

  defp appearance(assigns) do
    ~H"""
    <section id="appearance" aria-labelledby="appearance-title">
      <.section_heading id="appearance-title">Aussehen</.section_heading>
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
      <.empty_state :if={!@status} icon="history">Noch nichts aus YNAB übernommen.</.empty_state>
      <div :if={@status} class="flex flex-wrap items-center gap-2">
        <.badge tone={:success}>abgeschlossen</.badge>
        <span class="text-sm text-base-content/70">
          übernommen am {Format.date(DateTime.to_date(@status.imported_at))}
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
  defp counted(number, _one, many), do: "#{Format.count(number)} #{many}"

  @impl true
  def mount(_params, _session, socket), do: {:ok, socket}

  @impl true
  def handle_params(_params, _url, socket) do
    section = section(socket.assigns.live_action)
    if section == :ynab, do: ensure_budget!(socket.assigns.current_scope)

    {:noreply,
     socket
     |> assign(:section, section)
     |> assign(:page_title, if(section, do: Components.label(section), else: "Einstellungen"))
     |> assign(:ynab_status, if(section == :ynab, do: YnabImport.status()))}
  end

  defp ensure_budget!(scope),
    do: Areas.allowed?(scope, :budget) || raise(AbakusWeb.NotFoundError)

  defp section(:index), do: nil
  defp section(section), do: section
end
