defmodule AbakusWeb.Bookkeeping.InvoiceFormLive do
  @moduledoc """
  „Neue Rechnung“: a customer, the invoice date and the service period, the VAT and the positions as quantity ×
  unit × price, with the amounts they add up to. Writing it, after asking, gives it the next number for good and
  leads to „Rechnungen“. Without a complete sender in the settings, or without customers, it says where to add them.
  """
  use AbakusWeb, :live_view

  alias Abakus.Bookkeeping.{Invoice, Invoices, Position, Settings}
  alias Abakus.{LocalTime, Money}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      areas={@areas}
      area={@area}
      current={:bookkeeping_invoices}
    >
      <.header>
        Neue Rechnung
        <:subtitle>Die Nummer vergibt Abakus beim Schreiben, fortlaufend über die Jahre.</:subtitle>
      </.header>

      <.alert :if={!@sender?} id="invoice-no-sender" tone={:warning}>
        Für Rechnungen fehlt noch der Absender mit Anschrift, IBAN und Steuernummer oder USt-IdNr.
        <.link navigate={~p"/settings/buchhaltung/invoices"} class="link">Zu den Einstellungen</.link>
      </.alert>

      <.alert :if={@customers == []} id="invoice-no-customers" tone={:warning}>
        Noch keine Kunden.
        <.link navigate={~p"/buchhaltung/customers"} class="link">Kunden anlegen</.link>
      </.alert>

      <.form for={@form} id="invoice-form" phx-change="validate" phx-submit="write" class="mt-4">
        <div class="grid gap-x-4 sm:grid-cols-2">
          <.input
            field={@form[:customer_id]}
            type="select"
            label="Kunde"
            options={Enum.map(@customers, &{&1.name, &1.id})}
            prompt="Bitte wählen"
          />
          <.input field={@form[:vat]} type="select" label="Umsatzsteuer" options={vat_options()} />
          <.input field={@form[:date]} type="date" label="Rechnungsdatum" />
          <div class="grid grid-cols-2 gap-x-4">
            <.input field={@form[:service_from]} type="date" label="Leistung vom" />
            <.input field={@form[:service_to]} type="date" label="bis" />
          </div>
        </div>

        <.section_heading id="invoice-positions-heading">Positionen</.section_heading>
        <div id="invoice-positions" class="flex flex-col gap-2">
          <.inputs_for :let={position} field={@form[:positions]}>
            <input type="hidden" name="invoice[positions_sort][]" value={position.index} />
            <.field_row id={"invoice-position-#{position.index}"}>
              <.input field={position[:description]} label="Leistung" bare class="input-sm" />
              <.input
                field={position[:quantity]}
                label="Menge"
                bare
                numeric
                inputmode="decimal"
                class="input-sm w-20"
              />
              <.input
                field={position[:unit]}
                type="select"
                label="Einheit"
                options={Position.unit_options()}
                bare
                class="select-sm w-28"
              />
              <.input
                field={position[:unit_price]}
                label="Einzelpreis"
                bare
                numeric
                inputmode="decimal"
                suffix="€"
                value={price_value(position[:unit_price].value)}
                class="input-sm w-28"
              />
              <.button
                id={"invoice-position-#{position.index}-remove"}
                type="button"
                variant={:ghost}
                size={:sm}
                icon="minus"
                icon_only
                label="Position entfernen"
                name="invoice[positions_drop][]"
                value={position.index}
                phx-click={JS.dispatch("change")}
              />
            </.field_row>
          </.inputs_for>
          <input type="hidden" name="invoice[positions_drop][]" />
          <.field_error field={@form[:positions]} />
          <div>
            <.button
              id="invoice-position-add"
              type="button"
              size={:sm}
              icon="plus"
              name="invoice[positions_sort][]"
              value="new"
              phx-click={JS.dispatch("change")}
            >
              Position hinzufügen
            </.button>
          </div>
        </div>

        <dl
          id="invoice-amounts"
          class="mt-6 ms-auto grid max-w-xs grid-cols-[1fr_auto] gap-x-6 gap-y-1 text-sm"
        >
          <dt>Netto</dt>
          <dd class="text-end tabular-nums">{Money.euros(@amounts.net)}</dd>
          <dt>{vat_label(@vat)}</dt>
          <dd class="text-end tabular-nums">{Money.euros(@amounts.vat)}</dd>
          <dt class="font-semibold">Gesamt</dt>
          <dd id="invoice-total" class="text-end font-semibold tabular-nums">
            {Money.euros(@amounts.total)}
          </dd>
        </dl>

        <.action_bar class="mt-6">
          <.button navigate={~p"/buchhaltung/invoices"}>Abbrechen</.button>
          <.button
            id="invoice-write"
            type="submit"
            variant={:primary}
            disabled={!@sender? or @customers == []}
            confirm="Rechnung schreiben?"
            confirm_text="Sie bekommt die nächste Nummer und lässt sich danach nicht mehr ändern."
            confirm_label="Schreiben"
          >
            Rechnung schreiben
          </.button>
        </.action_bar>
      </.form>
    </Layouts.app>
    """
  end

  defp vat_options do
    [{"19 %", "19"}, {"7 %", "7"}, {"Reverse Charge (Kunde im EU-Ausland)", "reverse_charge"}]
  end

  defp vat_label(:reverse_charge), do: "Umsatzsteuer (Reverse Charge)"
  defp vat_label(treatment), do: "Umsatzsteuer #{Invoice.rate(treatment)} %"

  defp price_value(cents) when is_integer(cents), do: Money.amount(cents)
  defp price_value(text), do: text

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    {:ok,
     socket
     |> assign(
       page_title: "Neue Rechnung",
       customers: Invoices.list_customers(scope),
       sender?: Settings.complete?(Invoices.get_settings(scope))
     )
     |> assign_form(Invoices.change_invoice(Invoices.new_invoice(LocalTime.today())))}
  end

  @impl true
  def handle_event("validate", %{"invoice" => params}, socket) do
    changeset = Invoices.new_invoice(LocalTime.today()) |> Invoices.change_invoice(params)
    {:noreply, assign_form(socket, Map.put(changeset, :action, :validate))}
  end

  def handle_event("write", %{"invoice" => params}, socket) do
    case Invoices.write_invoice(socket.assigns.current_scope, params) do
      {:ok, invoice} ->
        {:noreply,
         socket
         |> put_flash(:info, "Rechnung #{invoice.number} geschrieben.")
         |> push_navigate(to: ~p"/buchhaltung/invoices")}

      {:error, :no_sender} ->
        {:noreply,
         socket
         |> assign(:sender?, false)
         |> put_flash(:error, "Für Rechnungen fehlt der Absender.")}

      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp assign_form(socket, changeset) do
    positions =
      for %{valid?: true} = change <- Ecto.Changeset.get_embed(changeset, :positions),
          position = Ecto.Changeset.apply_changes(change),
          position.quantity && position.unit_price,
          do: position

    vat = Ecto.Changeset.get_field(changeset, :vat) || :rate_19

    assign(socket,
      form: to_form(changeset, as: :invoice),
      vat: vat,
      amounts: Invoice.amounts(positions, vat)
    )
  end
end
