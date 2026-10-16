defmodule AbakusWeb.Depot.PortfoliosLive do
  @moduledoc """
  „Depots“ in the settings: the user's active portfolios with their depot numbers, each edited in place, and a new
  portfolio with its Verrechnungskonto. The first one opens the Depot area.
  """
  use AbakusWeb, :depot_live_view

  alias Abakus.Depot.Portfolios
  alias AbakusWeb.Areas
  alias AbakusWeb.Depot.Format
  alias AbakusWeb.SettingsLive.Components

  @impl true
  def render(assigns) do
    ~H"""
    <Components.page
      section={:depots}
      flash={@flash}
      current_scope={@current_scope}
      areas={@areas}
      area={@area}
      account_groups={@account_groups}
      account_dialog={@account_dialog}
    >
      <div class="flex flex-col gap-8">
        <section :if={@active_portfolios != []} id="depot-numbers" aria-labelledby="depots-title">
          <.section_heading id="depots-title" count={length(@active_portfolios)}>
            Deine Depots
          </.section_heading>
          <p class="mb-3 max-w-prose text-sm text-base-content/70">
            Die Depotnummer, wie die Bank sie druckt; nur die Ziffern zählen.
          </p>
          <.list>
            <.depot_number_row
              :for={portfolio <- @active_portfolios}
              portfolio={portfolio}
              form={@editing == portfolio.id && @depot_number_form}
            />
          </.list>
        </section>

        <section id="new-portfolio" aria-labelledby="new-portfolio-title">
          <.section_heading id="new-portfolio-title">Depot anlegen</.section_heading>
          <p class="mb-3 max-w-prose text-sm text-base-content/70">
            Nur du siehst deine Depots. Käufe, Verkäufe und Dividenden laufen über ein
            Verrechnungskonto, das mit dem Depot angelegt wird.
          </p>
          <.form
            for={@new_form}
            id="new-portfolio-form"
            class="max-w-md"
            phx-change="validate_portfolio"
            phx-submit="create_portfolio"
          >
            <.input field={@new_form[:name]} label="Name" placeholder="z. B. Langfristig" />
            <.input field={@new_form[:account_name]} label="Verrechnungskonto" />
            <.action_bar class="mt-4">
              <.button type="submit" variant={:primary} icon="plus" phx-disable-with="Legt an …">
                Depot anlegen
              </.button>
            </.action_bar>
          </.form>
        </section>
      </div>
    </Components.page>
    """
  end

  attr :portfolio, :map, required: true
  attr :form, :any, required: true, doc: "the depot number's form while it is edited, else false"

  defp depot_number_row(%{form: false} = assigns) do
    ~H"""
    <.list_row id={"depot-number-#{@portfolio.id}"} title={Format.portfolio_name(@portfolio)}>
      <:leading><.icon name="briefcase" class="size-5 text-base-content/70" /></:leading>
      <:meta>
        <span :for={{part, index} <- Enum.with_index(depot_number_details(@portfolio))}><.meta_sep :if={
          index > 0
        } /><span class="whitespace-nowrap">{part}</span></span>
      </:meta>
      <:trailing>
        <.button
          size={:sm}
          phx-click="edit_depot_number"
          phx-value-id={@portfolio.id}
          aria-label={"#{depot_number_action(@portfolio)}: Depotnummer von „#{Format.portfolio_name(@portfolio)}“"}
        >
          {depot_number_action(@portfolio)}
        </.button>
      </:trailing>
    </.list_row>
    """
  end

  defp depot_number_row(assigns) do
    ~H"""
    <li id={"depot-number-#{@portfolio.id}"} class="list-row items-start">
      <.icon name="briefcase" class="mt-0.5 size-5 text-base-content/70" />
      <.form
        for={@form}
        id="depot-number-form"
        class="list-col-grow min-w-0"
        phx-change="validate_depot_number"
        phx-submit="save_depot_number"
        phx-window-keydown="cancel_depot_number"
        phx-key="Escape"
      >
        <p class="font-medium wrap-anywhere">{Format.portfolio_name(@portfolio)}</p>
        <div class="flex flex-col sm:flex-row sm:items-start sm:gap-2">
          <div class="sm:max-w-md sm:flex-1">
            <.input
              field={@form[:depot_number]}
              label={"Depotnummer von „#{Format.portfolio_name(@portfolio)}“"}
              inline
              class="tabular-nums"
              inputmode="numeric"
              autocomplete="off"
              spellcheck="false"
              placeholder="z. B. 123 456 7890"
              phx-mounted={JS.focus()}
            >
              <.button
                type="submit"
                variant={:primary}
                class="join-item"
                phx-disable-with="Speichert …"
              >
                Speichern
              </.button>
            </.input>
          </div>
          <.button variant={:ghost} class="sm:mt-1" phx-click="cancel_depot_number">
            Abbrechen
          </.button>
        </div>
      </.form>
    </li>
    """
  end

  defp depot_number_details(portfolio) do
    Enum.reject(
      [
        if(portfolio.depot_number,
          do: "Depotnummer #{Format.masked(portfolio.depot_number)}",
          else: "Keine Depotnummer"
        ),
        portfolio.reference_account && "Verrechnungskonto „#{portfolio.reference_account.name}“"
      ],
      &is_nil/1
    )
  end

  defp depot_number_action(%{depot_number: nil}), do: "Eintragen"
  defp depot_number_action(_portfolio), do: "Ändern"

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(page_title: "Depots", editing: nil, depot_number_form: nil)
     |> assign(:new_form, to_form(Portfolios.change_new_portfolio(), as: :portfolio))
     |> load_active_portfolios()}
  end

  @impl true
  def handle_event("validate_portfolio", %{"portfolio" => params}, socket) do
    form =
      params |> Portfolios.change_new_portfolio() |> to_form(as: :portfolio, action: :validate)

    {:noreply, assign(socket, :new_form, form)}
  end

  def handle_event("create_portfolio", %{"portfolio" => params}, socket) do
    case Portfolios.create_portfolio(socket.assigns.current_scope, params) do
      {:ok, portfolio} ->
        {:noreply,
         socket
         |> put_flash(:info, "Depot „#{Format.portfolio_name(portfolio)}“ angelegt.")
         |> assign(:new_form, to_form(Portfolios.change_new_portfolio(), as: :portfolio))
         |> open_depot()
         |> load_active_portfolios()}

      {:error, changeset} ->
        {:noreply, assign(socket, :new_form, to_form(changeset, as: :portfolio, action: :insert))}
    end
  end

  def handle_event("edit_depot_number", %{"id" => id}, socket) do
    case find_portfolio(socket, id) do
      nil -> {:noreply, socket}
      portfolio -> {:noreply, edit(socket, portfolio, %{})}
    end
  end

  def handle_event("validate_depot_number", %{"portfolio" => params}, socket) do
    case find_portfolio(socket, socket.assigns.editing) do
      nil -> {:noreply, socket}
      portfolio -> {:noreply, edit(socket, portfolio, params, :validate)}
    end
  end

  def handle_event("save_depot_number", %{"portfolio" => params}, socket) do
    case find_portfolio(socket, socket.assigns.editing) do
      nil -> {:noreply, socket}
      portfolio -> save(socket, portfolio, params)
    end
  end

  def handle_event("cancel_depot_number", _params, socket),
    do: {:noreply, assign(socket, editing: nil, depot_number_form: nil)}

  # The sidebar and the area switcher show the Depot as soon as it exists.
  defp open_depot(%{assigns: %{current_scope: %{depot: true}}} = socket), do: socket

  defp open_depot(socket) do
    scope = %{socket.assigns.current_scope | depot: true}

    assign(socket,
      current_scope: scope,
      areas: Areas.for_scope(scope),
      area: socket.assigns.area || :depot
    )
  end

  defp save(socket, portfolio, params) do
    case Portfolios.update_depot_number(socket.assigns.current_scope, portfolio, params) do
      {:ok, _portfolio} ->
        {:noreply,
         socket
         |> put_flash(:info, "Depotnummer von „#{Format.portfolio_name(portfolio)}“ gespeichert.")
         |> assign(editing: nil, depot_number_form: nil)
         |> load_active_portfolios()}

      {:error, changeset} ->
        {:noreply, assign(socket, :depot_number_form, to_form(changeset, action: :update))}
    end
  end

  defp edit(socket, portfolio, params, action \\ nil) do
    changeset = Portfolios.change_depot_number(socket.assigns.current_scope, portfolio, params)
    assign(socket, editing: portfolio.id, depot_number_form: to_form(changeset, action: action))
  end

  defp find_portfolio(socket, id),
    do: Enum.find(socket.assigns.active_portfolios, &(to_string(&1.id) == to_string(id)))

  defp load_active_portfolios(socket),
    do:
      assign(
        socket,
        :active_portfolios,
        Portfolios.list_active_portfolios(socket.assigns.current_scope)
      )
end
