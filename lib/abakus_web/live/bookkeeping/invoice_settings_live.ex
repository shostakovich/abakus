defmodule AbakusWeb.Bookkeeping.InvoiceSettingsLive do
  @moduledoc """
  „Rechnungen“ in the settings, for a user with the Buchhaltung: the sender their invoices name, with the tax
  number or VAT id, the IBAN they are paid to and the days until they are due. Written invoices keep the sender
  they had.
  """
  use AbakusWeb, :live_view

  alias Abakus.Bookkeeping.Settings
  alias AbakusWeb.{Areas, NotFoundError}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.settings
      current={:invoice_settings}
      flash={@flash}
      current_scope={@current_scope}
      areas={@areas}
      area={@area}
      groups={@settings_groups}
    >
      <.header>
        Rechnungen
        <:subtitle>
          Der Absender auf deinen Rechnungen. Geschriebene Rechnungen behalten ihren.
        </:subtitle>
      </.header>
      <.form for={@form} id="invoice-settings-form" phx-change="validate" phx-submit="save">
        <.input field={@form[:name]} label="Name" autocomplete="name" />
        <.input field={@form[:street]} label="Straße und Hausnummer" autocomplete="street-address" />
        <div class="grid grid-cols-[minmax(0,1fr)_minmax(0,2fr)] gap-x-4">
          <.input field={@form[:postal_code]} label="PLZ" autocomplete="postal-code" />
          <.input field={@form[:city]} label="Ort" autocomplete="address-level2" />
        </div>
        <div class="grid gap-x-4 sm:grid-cols-2">
          <.input field={@form[:tax_number]} label="Steuernummer" autocomplete="off" />
          <.input field={@form[:vat_id]} label="USt-IdNr." identifier autocomplete="off" />
        </div>
        <.input field={@form[:iban]} label="IBAN" identifier autocomplete="off" />
        <.input
          field={@form[:payment_days]}
          type="number"
          label="Zahlungsziel"
          suffix="Tage"
          min="0"
          max="365"
          class="max-w-40"
        />
        <.action_bar class="mt-4">
          <.button
            id="invoice-settings-save"
            type="submit"
            variant={:primary}
            saved
            phx-disable-with="Speichert …"
          >
            Speichern
          </.button>
        </.action_bar>
      </.form>
    </Layouts.settings>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope
    Areas.allowed?(scope, :bookkeeping) || raise NotFoundError

    settings = Settings.get_settings(scope)

    {:ok,
     assign(socket,
       page_title: "Rechnungen",
       settings: settings,
       form: to_form(Settings.change_settings(settings))
     )}
  end

  @impl true
  def handle_event("validate", %{"settings" => params}, socket) do
    changeset = Settings.change_settings(socket.assigns.settings, params)
    {:noreply, assign(socket, :form, to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"settings" => params}, socket) do
    case Settings.save_settings(socket.assigns.current_scope, params) do
      {:ok, settings} ->
        {:noreply,
         socket
         |> assign(settings: settings, form: to_form(Settings.change_settings(settings)))
         |> push_saved("invoice-settings-save")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end
end
