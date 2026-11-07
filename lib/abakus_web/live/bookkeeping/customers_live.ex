defmodule AbakusWeb.Bookkeeping.CustomersLive do
  @moduledoc """
  The Buchhaltung's „Kunden“: whom the user's invoices go to, by name, each with its address; a dialog adds or
  changes one. A written invoice keeps the customer as it was.
  """
  use AbakusWeb, :live_view

  alias Abakus.Bookkeeping.{Countries, Customer, Invoices}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      areas={@areas}
      area={@area}
      current={:bookkeeping_customers}
    >
      <.header>
        Kunden
        <:actions>
          <.button
            id="customer-new"
            variant={:primary}
            icon="plus"
            class="max-md:hidden"
            phx-click="new"
          >
            Neuer Kunde
          </.button>
        </:actions>
      </.header>
      <.list :if={@customers != []} id="customers">
        <.list_row
          :for={customer <- @customers}
          id={"customer-#{customer.id}"}
          title={customer.name}
          on_click={JS.push("edit", value: %{id: customer.id})}
        >
          <:meta>{join_meta(address(customer))}</:meta>
        </.list_row>
      </.list>
      <.empty_state
        :if={@customers == []}
        id="customers-empty"
        layout={:page}
        plush="users"
        icon="users"
        title="Noch keine Kunden"
      >
        Kunden bekommen die Rechnungen, mit Name, Anschrift und, im EU-Ausland, ihrer USt-IdNr.
      </.empty_state>
      <:fab><.fab id="fab-customer" label="Neuer Kunde" phx-click="new" /></:fab>

      <.modal
        :if={@form}
        id="customer-modal"
        show
        title={if @editing.id, do: "Kunde bearbeiten", else: "Neuer Kunde"}
        on_cancel={JS.push("close")}
      >
        <.form for={@form} id="customer-form" phx-change="validate" phx-submit="save">
          <.input field={@form[:name]} label="Name" autocomplete="off" />
          <.input field={@form[:street]} label="Straße und Hausnummer" autocomplete="off" />
          <div class="grid grid-cols-[minmax(0,1fr)_minmax(0,2fr)] gap-x-4">
            <.input field={@form[:postal_code]} label="PLZ" autocomplete="off" />
            <.input field={@form[:city]} label="Ort" autocomplete="off" />
          </div>
          <.input field={@form[:country]} type="select" label="Land" options={Countries.options()} />
          <.input
            field={@form[:vat_id]}
            label="USt-IdNr."
            identifier
            help="Für Rechnungen ins EU-Ausland mit Reverse Charge."
          />
          <.action_bar sticky>
            <.button phx-click={hide_modal("customer-modal")}>Abbrechen</.button>
            <.button
              id="customer-save"
              type="submit"
              variant={:primary}
              phx-disable-with="Speichern …"
            >
              Speichern
            </.button>
          </.action_bar>
        </.form>
      </.modal>
    </Layouts.app>
    """
  end

  defp address(customer) do
    country = if customer.country != "DE", do: [Countries.name(customer.country)], else: []
    [customer.street, "#{customer.postal_code} #{customer.city}"] ++ country
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket |> assign(page_title: "Kunden", form: nil, editing: nil) |> load()}
  end

  defp load(socket),
    do: assign(socket, :customers, Invoices.list_customers(socket.assigns.current_scope))

  @impl true
  def handle_event("new", _params, socket), do: {:noreply, open(socket, %Customer{})}

  def handle_event("edit", %{"id" => id}, socket) do
    case Invoices.get_customer(socket.assigns.current_scope, id) do
      nil -> {:noreply, socket |> put_flash(:error, "Kunde nicht gefunden.") |> load()}
      customer -> {:noreply, open(socket, customer)}
    end
  end

  def handle_event("close", _params, socket),
    do: {:noreply, assign(socket, form: nil, editing: nil)}

  def handle_event("validate", %{"customer" => params}, socket) do
    changeset = Invoices.change_customer(socket.assigns.editing, params)
    {:noreply, assign(socket, :form, to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"customer" => params}, socket) do
    case save(socket.assigns.current_scope, socket.assigns.editing, params) do
      {:ok, customer} ->
        {:noreply,
         socket
         |> put_flash(:info, "„#{customer.name}“ gespeichert.")
         |> assign(form: nil, editing: nil)
         |> load()}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  defp save(scope, %Customer{id: nil}, params), do: Invoices.create_customer(scope, params)
  defp save(scope, customer, params), do: Invoices.update_customer(scope, customer, params)

  defp open(socket, customer),
    do: assign(socket, editing: customer, form: to_form(Invoices.change_customer(customer)))
end
