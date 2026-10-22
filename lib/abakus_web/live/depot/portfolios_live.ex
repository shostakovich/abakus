defmodule AbakusWeb.Depot.PortfoliosLive do
  @moduledoc """
  „Depots“ in the settings: the user's portfolios, the retired ones apart, with their depot numbers, which find a
  receipt's portfolio, and their Verrechnungskonten, each edited in a dialog, and a new portfolio with its
  Verrechnungskonto, a new tracking account in Finanzen. A Verrechnungskonto that is a tracking account is the
  portfolio's cash, which no register shows, so it is renamed, closed and reopened here in `AbakusWeb.AccountDialog`; a
  budget account is edited in the budget. The first portfolio opens Finanzen. The budget owner links the Depot to the
  budget here (`Abakus.Depot.BudgetLink`), so its cash side goes into budget accounts too (`Abakus.Depot.CashSide`).
  """
  use AbakusWeb, :depot_live_view

  alias Abakus.Depot.{BudgetLink, Portfolios, Receipts}
  alias Abakus.{Format, Ledger}
  alias Abakus.Ledger.Account
  alias Abakus.Users.Scope
  alias AbakusWeb.{AccountDialog, Areas, SettingsNav}
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
        <section :if={@active != []} id="portfolios" aria-labelledby="depots-title">
          <.section_heading id="depots-title" count={length(@active)}>
            Deine Depots
          </.section_heading>
          <p class="mb-3 max-w-prose text-sm text-base-content/70">
            Belege finden ihr Depot über die Depotnummer, wie die Bank sie druckt; nur die Ziffern zählen.
          </p>
          <.list>
            <.portfolio_row :for={portfolio <- @active} portfolio={portfolio} />
          </.list>
        </section>

        <section :if={@retired != []} id="retired-portfolios" aria-labelledby="retired-title">
          <.section_heading id="retired-title" count={length(@retired)}>
            Aufgelöste Depots
          </.section_heading>
          <.list>
            <.portfolio_row :for={portfolio <- @retired} portfolio={portfolio} />
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
      <.portfolio_dialog :if={@editing} portfolio={@editing} form={@form} choices={@choices} />
      <.live_component
        :if={@account_dialog}
        module={AccountDialog}
        id="account-dialog"
        current_scope={@current_scope}
        account={@account_dialog.account}
        balance={@account_dialog.balance}
      />
    </Layouts.settings>
    """
  end

  attr :portfolio, :map, required: true

  defp portfolio_row(assigns) do
    ~H"""
    <.list_row id={"portfolio-row-#{@portfolio.id}"} title={DepotFormat.portfolio_name(@portfolio)}>
      <:leading><.plush name="briefcase" size={:lg} /></:leading>
      <:meta>
        <span :for={{part, index} <- Enum.with_index(details(@portfolio))}><.meta_sep :if={index > 0} /><span class="whitespace-nowrap">{part}</span></span>
      </:meta>
      <:action
        id={"portfolio-#{@portfolio.id}-edit"}
        label="Bearbeiten"
        icon="pencil"
        on_click={JS.push("edit", value: %{id: @portfolio.id})}
      />
      <:action
        :if={cash?(@portfolio)}
        id={"portfolio-#{@portfolio.id}-account"}
        label="Verrechnungskonto bearbeiten"
        icon="wallet"
        on_click={JS.push("edit_account", value: %{id: @portfolio.id})}
      />
    </.list_row>
    """
  end

  defp cash?(%{reference_account: %Account{} = account}), do: not Account.budget_account?(account)
  defp cash?(_portfolio), do: false

  attr :portfolio, :map, required: true
  attr :form, :any, required: true
  attr :choices, :map, required: true

  defp portfolio_dialog(assigns) do
    ~H"""
    <.modal
      id="portfolio-dialog"
      show
      title={DepotFormat.portfolio_name(@portfolio)}
      on_cancel={JS.push("cancel_edit")}
    >
      <.form for={@form} id="portfolio-form" phx-change="validate" phx-submit="save">
        <.input
          field={@form[:depot_number]}
          label="Depotnummer"
          class="tabular-nums"
          inputmode="numeric"
          autocomplete="off"
          spellcheck="false"
          placeholder="z. B. 123 456 7890"
        />
        <.input
          field={@form[:reference_account_id]}
          type="select"
          label="Verrechnungskonto"
          prompt="Konto wählen"
          options={account_options(@choices.accounts)}
          help="Käufe, Verkäufe und Dividenden laufen standardmäßig über dieses Konto. Ein Trackingkonto ist das Cash beim Broker und zählt zum Wert des Depots; ein Budgetkonto bleibt im Budget."
        />
        <.action_bar class="mt-4">
          <.button phx-click="cancel_edit">Abbrechen</.button>
          <.button type="submit" variant={:primary} phx-disable-with="Speichert …">
            Speichern
          </.button>
        </.action_bar>
      </.form>
    </.modal>
    """
  end

  defp account_options(accounts) do
    {budget, tracking} = Enum.split_with(accounts, &Account.budget_account?/1)

    for {label, group} <- [{"Budgetkonten", budget}, {"Trackingkonten", tracking}],
        group != [],
        do: {label, Enum.map(group, &{&1.name, &1.id})}
  end

  defp details(portfolio) do
    [
      if(portfolio.depot_number,
        do: "Depotnummer #{DepotFormat.masked(portfolio.depot_number)}",
        else: "Keine Depotnummer"
      ),
      portfolio.reference_account &&
        "Verrechnungskonto „#{portfolio.reference_account.name}“"
    ]
    |> Enum.filter(& &1)
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(page_title: "Depots", editing: nil, form: nil, choices: nil, account_dialog: nil)
     |> load_link()
     |> assign(:new_form, to_form(Portfolios.change_new_portfolio(), as: :portfolio))
     |> load_portfolios()}
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
         |> load_portfolios()}

      {:error, changeset} ->
        {:noreply, assign(socket, :new_form, to_form(changeset, as: :portfolio, action: :insert))}
    end
  end

  def handle_event("edit", %{"id" => id}, socket) do
    case find_portfolio(socket, id) do
      nil -> {:noreply, socket}
      portfolio -> {:noreply, edit(socket, portfolio)}
    end
  end

  def handle_event("edit_account", %{"id" => id}, socket) do
    case find_portfolio(socket, id) do
      %{reference_account: account} = portfolio ->
        if cash?(portfolio),
          do: {:noreply, assign(socket, :account_dialog, account_dialog(socket, account))},
          else: {:noreply, socket}

      nil ->
        {:noreply, socket}
    end
  end

  def handle_event("close_account_dialog", _params, socket),
    do: {:noreply, assign(socket, :account_dialog, nil)}

  def handle_event("validate", %{"portfolio" => params}, %{assigns: %{editing: %{}}} = socket) do
    %{current_scope: scope, editing: portfolio, choices: choices} = socket.assigns
    changeset = Portfolios.change_portfolio(scope, portfolio, params, choices)

    {:noreply, assign(socket, :form, to_form(changeset, id: "portfolio-form", action: :validate))}
  end

  def handle_event("save", %{"portfolio" => params}, %{assigns: %{editing: %{}}} = socket),
    do: save(socket, socket.assigns.editing, params)

  def handle_event(event, _params, socket) when event in ~w(validate save), do: {:noreply, socket}

  def handle_event("cancel_edit", _params, socket),
    do: {:noreply, assign(socket, editing: nil, form: nil, choices: nil)}

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

  @impl true
  def handle_info({AccountDialog, :done, message, _result}, socket) do
    {:noreply,
     socket
     |> assign(:account_dialog, nil)
     |> put_flash(:info, message)
     |> load_portfolios()}
  end

  defp account_dialog(socket, account) do
    balances = Ledger.balances(socket.assigns.current_scope)
    %{account: account, balance: get_in(balances, [account.id, :balance]) || 0}
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

    case Portfolios.update_portfolio(scope, portfolio, params) do
      {:ok, _portfolio} ->
        Receipts.recheck(scope)

        {:noreply,
         socket
         |> put_flash(:info, "Depot „#{DepotFormat.portfolio_name(portfolio)}“ gespeichert.")
         |> assign(editing: nil, form: nil, choices: nil)
         |> load_portfolios()}

      {:error, changeset} ->
        {:noreply,
         assign(socket, :form, to_form(changeset, id: "portfolio-form", action: :update))}
    end
  end

  defp edit(socket, portfolio) do
    scope = socket.assigns.current_scope
    choices = Portfolios.account_choices(scope, portfolio)
    changeset = Portfolios.change_portfolio(scope, portfolio, %{}, choices)

    assign(socket,
      editing: portfolio,
      form: to_form(changeset, id: "portfolio-form"),
      choices: choices
    )
  end

  defp find_portfolio(socket, id),
    do:
      Enum.find(
        socket.assigns.active ++ socket.assigns.retired,
        &(to_string(&1.id) == to_string(id))
      )

  defp load_portfolios(socket) do
    {retired, active} =
      socket.assigns.current_scope
      |> Portfolios.list_portfolios_with_accounts()
      |> Enum.split_with(& &1.retired)

    assign(socket, active: active, retired: retired)
  end
end
