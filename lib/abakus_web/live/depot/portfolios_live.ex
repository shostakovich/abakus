defmodule AbakusWeb.Depot.PortfoliosLive do
  @moduledoc """
  „Depots“ in the settings: the user's active portfolios with their depot numbers, which find a receipt's
  portfolio, each edited in place, and a new portfolio with its Verrechnungskonto. The first one opens
  Finanzen. The budget owner also picks the tracking account each portfolio and Verrechnungskonto feeds.
  """
  use AbakusWeb, :depot_live_view

  alias Abakus.Depot.{BudgetFeed, Portfolios, Receipts}
  alias AbakusWeb.{Areas, SettingsNav}
  alias AbakusWeb.Depot.Format

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

        <section :if={@feed_rows != []} id="budget-feeds" aria-labelledby="budget-feeds-title">
          <.section_heading id="budget-feeds-title">Im Budget</.section_heading>
          <p class="mb-3 max-w-prose text-sm text-base-content/70">
            Jeden Tag nach der Kursabfrage um 18 Uhr bucht das Depot den Wert der Depots und Verrechnungskonten
            als „Wertänderung“ in ihr Tracking-Konto, das dann niemand sonst mehr bucht.
          </p>
          <p :if={@feed_options == []} id="budget-feeds-none" class="max-w-prose">
            Dafür braucht das Budget ein offenes Tracking-Konto.
          </p>
          <.form
            :if={@feed_options != []}
            for={@feed_form}
            id="budget-feeds-form"
            class="max-w-md"
            phx-submit="save_feeds"
          >
            <.input
              :for={{key, label} <- @feed_rows}
              field={@feed_form[key]}
              type="select"
              label={label}
              prompt="– nicht im Budget –"
              options={@feed_options}
            />
            <.action_bar class="mt-4">
              <.button type="submit" variant={:primary} icon="save" phx-disable-with="Speichert …">
                Speichern
              </.button>
            </.action_bar>
          </.form>
        </section>

        <section id="new-portfolio" aria-labelledby="new-portfolio-title">
          <.section_heading id="new-portfolio-title">Depot anlegen</.section_heading>
          <p class="mb-3 max-w-prose text-sm text-base-content/70">
            Nur du siehst deine Depots. Käufe, Verkäufe und Dividenden laufen über ein
            Verrechnungskonto, das mit dem Depot angelegt wird. Oder <.link
              id="new-portfolio-import"
              href={~p"/depot/import"}
              class="link"
            >importiere eine Datei aus Portfolio Performance</.link>.
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
     |> load_active_portfolios()
     |> load_feeds()}
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
         |> Areas.open_depot()
         |> SettingsNav.assign_groups()
         |> load_active_portfolios()
         |> load_feeds()}

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

  def handle_event("save_feeds", params, socket) do
    feeds = params |> Map.get("feeds", %{}) |> Enum.flat_map(&feed/1) |> Map.new()

    case BudgetFeed.put_feeds(socket.assigns.current_scope, feeds) do
      {:ok, _feeds} ->
        {:noreply,
         socket |> put_flash(:info, "Zuordnung zum Budget gespeichert.") |> load_feeds()}

      {:error, _reason} ->
        {:noreply,
         put_flash(socket, :error, "Unbekanntes Depot oder Konto. Bitte die Seite neu laden.")}
    end
  end

  defp feed({"portfolio-" <> id, account_id}), do: [{{:portfolio, id}, account_id}]
  defp feed({"account-" <> id, account_id}), do: [{{:account, id}, account_id}]
  defp feed(_param), do: []

  defp save(socket, portfolio, params) do
    scope = socket.assigns.current_scope

    case Portfolios.update_depot_number(scope, portfolio, params) do
      {:ok, _portfolio} ->
        Receipts.recheck(scope)

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

  defp load_feeds(%{assigns: %{current_scope: %{user: %{budget_owner: true}} = scope}} = socket) do
    feeds = BudgetFeed.feeds(scope)

    assign(socket,
      feed_rows: feed_rows(scope, feeds),
      feed_options: feed_options(feeds),
      feed_form:
        to_form(Map.new(feeds, fn {key, account_id} -> {feed_key(key), account_id} end),
          as: :feeds
        )
    )
  end

  defp load_feeds(socket), do: assign(socket, feed_rows: [], feed_options: [], feed_form: nil)

  defp feed_options(feeds) do
    Enum.map(BudgetFeed.account_choices(), &{&1.name, &1.id}) ++
      for account <- BudgetFeed.fed_accounts_not_offered(feeds),
          do:
            {if(account.closed, do: "#{account.name} (geschlossen)", else: account.name),
             account.id}
  end

  # Retired portfolios and accounts only while they feed an account.
  defp feed_rows(scope, feeds) do
    portfolios =
      for portfolio <- Portfolios.list_portfolios(scope),
          shown_feed?(portfolio, feeds, {:portfolio, portfolio.id}),
          do:
            {feed_key({:portfolio, portfolio.id}), "Depot „#{Format.portfolio_name(portfolio)}“"}

    accounts =
      for account <- Portfolios.list_accounts(scope),
          shown_feed?(account, feeds, {:account, account.id}),
          do: {feed_key({:account, account.id}), "Verrechnungskonto „#{account.name}“"}

    portfolios ++ accounts
  end

  defp shown_feed?(item, feeds, key), do: not item.retired or Map.has_key?(feeds, key)

  defp feed_key({kind, id}), do: "#{kind}-#{id}"

  defp load_active_portfolios(socket),
    do:
      assign(
        socket,
        :active_portfolios,
        Portfolios.list_active_portfolios(socket.assigns.current_scope)
      )
end
