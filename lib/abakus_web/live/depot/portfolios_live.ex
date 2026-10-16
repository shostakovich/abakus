defmodule AbakusWeb.Depot.PortfoliosLive do
  @moduledoc """
  „Depots“ in the settings: the user's active portfolios with their depot numbers, which find a receipt's
  portfolio, their Verrechnungskonten with their roles (`Abakus.Depot.AccountRoles`), each edited in place, and a
  new portfolio with its Verrechnungskonto. The first one opens Finanzen. A portfolio of the budget owner is also a
  tracking account (`Abakus.Depot.BudgetFeed`), and the budget owner links the Depot's cash flows to the budget here
  (`Abakus.Depot.BudgetLink`).
  """
  use AbakusWeb, :depot_live_view

  alias Abakus.Depot.{AccountRoles, BudgetLink, Portfolios, Receipts}
  alias Abakus.Depot.Portfolios.Account
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

        <section :if={@accounts != []} id="clearing-accounts" aria-labelledby="accounts-title">
          <.section_heading id="accounts-title" count={length(@accounts)}>
            Verrechnungskonten
          </.section_heading>
          <p class="mb-3 max-w-prose text-sm text-base-content/70">
            Jedes Verrechnungskonto ist ein Budgetkonto, wenn es dasselbe Bankkonto ist, oder das Cash
            eines Depots, das zu dessen Wert zählt, oder keins von beiden.
          </p>
          <.list>
            <.account_role_row
              :for={account <- @accounts}
              account={account}
              form={@editing_role == account.id && @role_form}
              options={@editing_role == account.id && @role_options}
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
            das von dort ins Cash eines Depots geht oder zurück. Betrag, Datum und Empfänger folgen dem
            Depot; Kategorie, Memo und Bestätigung änderst du im Budget.
          </p>
          <p :if={!@link} id="budget-link-state" class="mb-3 max-w-prose text-sm text-base-content/70">
            Noch nicht mit dem Budget verknüpft. Danach ist jeder Kauf, Verkauf und jede Dividende über ein
            Verrechnungskonto, das ein Budgetkonto ist, eine Buchung in diesem Budgetkonto: Käufe als Ausgabe
            in der gewählten Kategorie, Einnahmen unter „Zu verteilen“. Buchungen vor dem Startdatum bleiben
            nur im Depot.
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

  attr :account, Account, required: true
  attr :form, :any, required: true, doc: "the role's form while it is edited, else false"
  attr :options, :any, required: true, doc: "the roles to choose from while it is edited"

  defp account_role_row(%{form: false} = assigns) do
    ~H"""
    <.list_row id={"clearing-account-#{@account.id}"} title={@account.name}>
      <:leading><.icon name="wallet" class="size-5 text-base-content/70" /></:leading>
      <:meta>
        <span class="whitespace-nowrap">{@account.currency}</span><.meta_sep /><span
          :if={Account.role(@account)}
          class="whitespace-nowrap"
        >{role_label(@account)}</span><.badge :if={!Account.role(@account)} tone={:warning}>
          Rolle fehlt
        </.badge>
      </:meta>
      <:trailing>
        <.button
          size={:sm}
          phx-click="edit_role"
          phx-value-id={@account.id}
          aria-label={"#{role_action(@account)}: Rolle von „#{@account.name}“"}
        >
          {role_action(@account)}
        </.button>
      </:trailing>
    </.list_row>
    """
  end

  defp account_role_row(assigns) do
    ~H"""
    <li id={"clearing-account-#{@account.id}"} class="list-row items-start">
      <.icon name="wallet" class="mt-0.5 size-5 text-base-content/70" />
      <.form
        for={@form}
        id="account-role-form"
        class="list-col-grow min-w-0"
        phx-submit="save_role"
        phx-window-keydown="cancel_role"
        phx-key="Escape"
      >
        <p class="font-medium wrap-anywhere">{@account.name}</p>
        <div class="flex flex-col sm:flex-row sm:items-start sm:gap-2">
          <div class="sm:max-w-md sm:flex-1">
            <.input
              field={@form[:role]}
              type="select"
              label={"Rolle von „#{@account.name}“"}
              prompt="Rolle wählen"
              options={@options}
              phx-mounted={JS.focus()}
            />
          </div>
          <div class="flex gap-2 sm:mt-1">
            <.button type="submit" variant={:primary} phx-disable-with="Speichert …">
              Speichern
            </.button>
            <.button variant={:ghost} phx-click="cancel_role">Abbrechen</.button>
          </div>
        </div>
      </.form>
    </li>
    """
  end

  defp role_label(%Account{} = account) do
    case Account.role(account) do
      {:budget_account, _id} ->
        "ist Budgetkonto „#{account.budget_account.name}“"

      {:portfolio_cash, _id} ->
        "Cash von Depot „#{DepotFormat.portfolio_name(account.cash_of_portfolio)}“"

      :none ->
        "keine Rolle"
    end
  end

  defp role_action(account), do: if(Account.role(account), do: "Ändern", else: "Festlegen")

  defp role_options(scope, account) do
    %{budget_accounts: budget_accounts, portfolios: portfolios} =
      AccountRoles.choices(scope, account)

    [
      {"Budgetkonto",
       for(
         a <- budget_accounts,
         do: {"ist Budgetkonto „#{a.name}“", AccountRoles.param({:budget_account, a.id})}
       )},
      {"Cash",
       for(
         p <- portfolios,
         do:
           {"Cash von Depot „#{DepotFormat.portfolio_name(p)}“",
            AccountRoles.param({:portfolio_cash, p.id})}
       )},
      {"Keine", [{"keine Rolle", AccountRoles.param(:none)}]}
    ]
    |> Enum.reject(fn {_group, options} -> options == [] end)
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
     |> assign(editing_role: nil, role_form: nil, role_options: nil)
     |> load_link()
     |> load_accounts()
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
         |> load_active_portfolios()
         |> load_accounts()}

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

  def handle_event("edit_role", %{"id" => id}, socket) do
    case find_account(socket, id) do
      nil ->
        {:noreply, socket}

      account ->
        {:noreply,
         assign(socket,
           editing_role: account.id,
           role_form: role_form(%{"role" => AccountRoles.param(Account.role(account))}),
           role_options: role_options(socket.assigns.current_scope, account)
         )}
    end
  end

  def handle_event("save_role", %{"role" => params}, socket) do
    case find_account(socket, socket.assigns.editing_role) do
      nil -> {:noreply, socket}
      account -> save_role(socket, account, params)
    end
  end

  def handle_event("cancel_role", _params, socket), do: {:noreply, close_role(socket)}

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
    case socket.assigns.link && BudgetLink.change_category(socket.assigns.link, id) do
      {:ok, _link} ->
        {:noreply, socket |> put_flash(:info, "Kategorie für Käufe gespeichert.") |> load_link()}

      {:error, changeset} ->
        {:noreply, assign(socket, :link_form, to_form(changeset, as: :link, action: :update))}

      nil ->
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

  defp save_role(socket, account, params) do
    case AccountRoles.set_role(socket.assigns.current_scope, account, params["role"]) do
      {:ok, _account} ->
        {:noreply,
         socket
         |> put_flash(:info, "Rolle von „#{account.name}“ gespeichert.")
         |> close_role()
         |> load_accounts()}

      {:error, message} ->
        {:noreply, assign(socket, :role_form, role_form(params, role: {message, []}))}
    end
  end

  defp role_form(params, errors \\ []),
    do: to_form(params, as: :role, errors: errors, action: if(errors != [], do: :update))

  defp close_role(socket),
    do: assign(socket, editing_role: nil, role_form: nil, role_options: nil)

  defp find_account(socket, id),
    do: Enum.find(socket.assigns.accounts, &(to_string(&1.id) == to_string(id)))

  defp load_accounts(socket),
    do: assign(socket, :accounts, AccountRoles.list_accounts(socket.assigns.current_scope))

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
