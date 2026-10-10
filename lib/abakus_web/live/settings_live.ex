defmodule AbakusWeb.SettingsLive do
  @moduledoc """
  The settings' overview and the sections that need no recent sign-in: Aussehen (the theme, per device) and the
  YNAB import's status, read from the data. Zugang & API is `AbakusWeb.UserLive.Settings`, behind the sudo plug.
  """
  use AbakusWeb, :live_view

  alias Abakus.YnabImport
  alias AbakusWeb.Format
  alias AbakusWeb.SettingsLive.Components

  @impl true
  def render(assigns) do
    ~H"""
    <Components.page
      section={@section}
      flash={@flash}
      current_scope={@current_scope}
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
    <.card title="Aussehen" id="appearance">
      <p class="text-body-secondary">Gilt für dieses Gerät.</p>
      <Layouts.theme_switch />
      <p class="small text-body-secondary mt-3 mb-0">
        Als App installieren: im Browser „Zum Home-Bildschirm“ wählen.
      </p>
    </.card>
    """
  end

  attr :status, YnabImport.Status

  defp ynab_import(assigns) do
    ~H"""
    <.card title="YNAB-Import" id="ynab-import">
      <p :if={!@status} class="fst-italic">Noch nichts aus YNAB übernommen.</p>
      <%= if @status do %>
        <div class="d-flex align-items-center gap-2 mb-2">
          <span class="badge text-bg-success">abgeschlossen</span>
          <span class="small text-body-secondary">
            übernommen am {Format.date(DateTime.to_date(@status.imported_at))}
          </span>
        </div>
        <p id="ynab-import-summary">Aus YNAB übernommen: {summary(@status)}.</p>
      <% end %>
      <p class="small text-body-secondary mb-0">
        Ein neuer Import ersetzt das ganze Budget. Sobald Abakus eigene Buchungen hat, läuft er nicht mehr.
      </p>
    </.card>
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

    {:noreply,
     socket
     |> assign(:section, section)
     |> assign(:page_title, if(section, do: Components.label(section), else: "Einstellungen"))
     |> assign(:ynab_status, if(section == :ynab, do: YnabImport.status()))}
  end

  defp section(:index), do: nil
  defp section(section), do: section
end
