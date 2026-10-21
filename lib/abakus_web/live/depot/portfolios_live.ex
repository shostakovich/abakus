defmodule AbakusWeb.Depot.PortfoliosLive do
  @moduledoc """
  „Depots“ in the settings: the user's active portfolios with their depot numbers, which find a receipt's
  portfolio, each edited in place, and a new portfolio with its Verrechnungskonto, a new tracking account in
  Finanzen. The first one opens Finanzen. The budget owner links the Depot to the budget here
  (`Abakus.Depot.BudgetLink`), so its cash side goes into budget accounts too (`Abakus.Depot.CashSide`).
  """
  use AbakusWeb, :depot_live_view

  alias Abakus.Depot.{BudgetLink, Portfolios, Receipts}
  alias Abakus.Format
  alias Abakus.Users.Scope
  alias AbakusWeb.{Areas, SettingsNav}
  alias AbakusWeb.Depot.Format, as: DepotFormat

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.settings
      current={:depots}
      flash={@flash}
      current_scope={@current_scope}
      areas={@areas}
      area={@area}
      groups={@settings_groups}
    >
      <.header>Depots</.header>
      <div class="flex flex-col gap-8">
        <section :if={@active_portfolios != []} id="depot-numbers" aria-labelledby="depots-title">
          <.section_heading id="depots-title" count={length(@active_portfolios)}>
            Deine Depots
          </.section_heading>
          <p class="mb-3 max-w-prose text-sm text-base-content/70">
            Belege finden ihr Depot über die Depotnummer, wie die Bank sie druckt; nur die Ziffern zählen.
          </p>
          <.list>
            <.depot_number_row
              :for={portfolio <- @active_portfolios}
              portfolio={portfolio}
              form={@editing == portfolio.id && @depot_number_form}
            />
          </.list>
        </section>

        <section
          :if={Scope.budget_owner?(@current_scope)}
          id="budget-link"
          aria-labelledby="budget-link-title"
        >
          <.section_heading id="budget-link-title">Budget</.section_heading>
          <p :if={@link} id="budget-link-state" class="mb-3 max-w-prose text-sm text-base-content/70">
            Seit dem {Format.date(@link.start_date)} ist jeder Kauf, Verkauf und jede Dividende über ein
            Verrechnungskonto, das ein Budgetkonto ist, eine Buchung in diesem Budgetkonto, ebenso Geld,
            das von dort auf ein anderes Verrechnungskonto geht oder zurück, als Umbuchung. Betrag, Datum
            und Empfänger folgen dem Depot; Kategorie, Memo und Bestätigung änderst du im Budget.
          </p>
          <p :if={!@link} id="budget-link-state" class="mb-3 max-w-prose text-sm text-base-content/70">
            Noch nicht mit dem Budget verknüpft. Danach ist jeder Kauf, Verkauf und jede Dividende über ein
            Verrechnungskonto, das ein Budgetkonto ist, eine Buchung in diesem Budgetkonto: Käufe als Ausgabe
            in der gewählten Kategorie, Einnahmen unter „Zu verteilen“. Buchungen vor dem Startdatum kommen
            nicht ins Budgetkonto.
          </p>
          <.form
            :if={!@link}
            for={@link_form}
            id="budget-link-form"
            class="max-w-md"
            phx-change="validate_link"
            phx-submit="switch_on"
          >
            <.input field={@link_form[:start_date]} type="date" label="Ab" required />
            <.input
              field={@link_form[:category_id]}
              type="select"
              label="Kategorie für Käufe"
              prompt="Kategorie wählen"
              options={@category_options}
              required
            />
            <.action_bar class="mt-4">
              <.button
                id="budget-link-submit"
                type="submit"
                variant={:primary}
                icon="link"
                confirm="Mit Budget verknüpfen?"
                confirm_text="Das lässt sich nicht rückgängig machen."
                confirm_label="Verknüpfen"
              >
                Mit Budget verknüpfen
              </.button>
            </.action_bar>
          </.form>
          <.form
            :if={@link}
            for={@link_form}
            id="budget-category-form"
            class="max-w-md"
            phx-submit="save_category"
          >
            <.input
              field={@link_form[:category_id]}
              type="select"
              label="Kategorie für neue Käufe"
              options={@category_options}
              required
            />
            <.action_bar class="mt-4">
              <.button type="submit" variant={:primary} phx-disable-with="Speichert …">
                Speichern
              </.button>
            </.action_bar>
          </.form>
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
    </Layouts.settings>
    """
  end

  attr :portfolio, :map, required: true
  attr :form, :any, required: true, doc: "the depot number's form while it is edited, else false"

  defp depot_number_row(%{form: false} = assigns) do
    ~H"""
    <.list_row id={"depot-number-#{@portfolio.id}"} title={DepotFormat.portfolio_name(@portfolio)}>
      <:leading><.plush name="briefcase" size={:lg} /></:leading>
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
          aria-label={"#{depot_number_action(@portfolio)}: Depotnummer von „#{DepotFormat.portfolio_name(@portfolio)}“"}
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
      <.plush name="briefcase" size={:lg} />
      <.form
        for={@form}
        id="depot-number-form"
        class="list-col-grow min-w-0"
        phx-change="validate_depot_number"
        phx-submit="save_depot_number"
        phx-window-keydown="cancel_depot_number"
        phx-key="Escape"
      >
        <p class="font-medium wrap-anywhere">{DepotFormat.portfolio_name(@portfolio)}</p>
        <div class="flex flex-col sm:flex-row sm:items-start sm:gap-2">
          <div class="sm:max-w-md sm:flex-1">
            <.input
              field={@form[:depot_number]}
              label={"Depotnummer von „#{DepotFormat.portfolio_name(@portfolio)}“"}
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
          do: "Depotnummer #{DepotFormat.masked(portfolio.depot_number)}",
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
     |> load_link()
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
         |> put_flash(:info, "Depot „#{DepotFormat.portfolio_name(portfolio)}“ angelegt.")
         |> assign(:new_form, to_form(Portfolios.change_new_portfolio(), as: :portfolio))
         |> Areas.open_depot()
         |> SettingsNav.assign_groups()
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

  def handle_event("validate_link", %{"link" => params}, socket),
    do: {:noreply, assign(socket, :link_form, to_form(BudgetLink.change_link(params), as: :link))}

  def handle_event("switch_on", %{"link" => params}, socket) do
    case BudgetLink.switch_on(socket.assigns.current_scope, params) do
      {:ok, _link} ->
        {:noreply, socket |> put_flash(:info, "Mit dem Budget verknüpft.") |> load_link()}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :link_form, to_form(changeset, as: :link, action: :insert))}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, link_refused(reason))}
    end
  end

  def handle_event("save_category", %{"link" => %{"category_id" => id}}, socket) do
    case BudgetLink.change_category(socket.assigns.current_scope, id) do
      {:ok, _link} ->
        {:noreply, socket |> put_flash(:info, "Kategorie für Käufe gespeichert.") |> load_link()}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :link_form, to_form(changeset, as: :link, action: :update))}

      {:error, :not_linked} ->
        {:noreply, socket}
    end
  end

  defp link_refused(:not_budget_owner), do: "Nur wer das Budget führt, kann es verknüpfen."
  defp link_refused(:linked), do: "Das Depot ist schon mit dem Budget verknüpft."
  defp link_refused(message) when is_binary(message), do: message

  defp load_link(%{assigns: %{current_scope: scope}} = socket) do
    if Scope.budget_owner?(scope), do: load_owned_link(socket, scope), else: no_link(socket)
  end

  defp load_owned_link(socket, scope) do
    link = BudgetLink.get(scope)

    assign(socket,
      link: link,
      link_form:
        to_form(if(link, do: Ecto.Changeset.change(link), else: BudgetLink.change_link()),
          as: :link
        ),
      category_options: BudgetLink.category_options(scope)
    )
  end

  defp no_link(socket), do: assign(socket, link: nil, link_form: nil, category_options: [])

  defp save(socket, portfolio, params) do
    scope = socket.assigns.current_scope

    case Portfolios.update_depot_number(scope, portfolio, params) do
      {:ok, _portfolio} ->
        Receipts.recheck(scope)

        {:noreply,
         socket
         |> put_flash(
           :info,
           "Depotnummer von „#{DepotFormat.portfolio_name(portfolio)}“ gespeichert."
         )
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
