defmodule AbakusWeb.Kasse.BudgetLinkLive do
  @moduledoc """
  "Budget-Verknüpfung", the budget owner's link between the Kasse and the budget: switching it on ("Mit Budget
  verknüpfen"), where their shares are booked and which budget category each Kasse category's shares land in.
  Anyone else gets 404.
  """
  use AbakusWeb, :kasse_live_view

  alias Abakus.Categories
  alias Abakus.Kasse.BudgetLink
  alias Abakus.Kasse.Categories, as: KasseCategories
  alias Abakus.Users.Scope

  @impl true
  def mount(_params, _session, socket) do
    if !Scope.budget_owner?(socket.assigns.current_scope), do: raise(AbakusWeb.NotFoundError)

    {:ok,
     socket
     |> assign(
       page_title: "Budget-Verknüpfung",
       budget_groups: budget_groups(socket.assigns.current_scope)
     )
     |> load_link()
     |> load()}
  end

  defp load_link(socket) do
    scope = socket.assigns.current_scope
    account = BudgetLink.account(scope)
    choices = if account, do: [], else: BudgetLink.account_choices(scope)
    fed = Enum.find(choices, &(&1.fed_by == :shared_expenses))

    assign(socket,
      account: account,
      account_options: Enum.map(choices, &{&1.name, &1.id}),
      start_date: if(!account, do: start_date(BudgetLink.start_date(scope))),
      link_form: to_form(%{"account_id" => fed && fed.id}, as: :link)
    )
  end

  defp start_date(%Date{} = date), do: Format.date(date)
  defp start_date(nil), do: nil

  defp budget_groups(scope) do
    for %{categories: [_ | _] = categories} = group <- Categories.list_category_groups(scope),
        do: {group.name, Enum.map(categories, &{&1.name, &1.id})}
  end

  defp load(socket) do
    scope = socket.assigns.current_scope
    mapping = BudgetLink.category_mapping(scope)

    rows =
      for category <- KasseCategories.list_categories(scope, :all),
          is_nil(category.archived_at) or Map.has_key?(mapping, category.id),
          do: category

    assign(socket,
      rows: rows,
      mapping_form: to_form(Map.new(rows, &{"#{&1.id}", mapping[&1.id] || ""}), as: :mapping)
    )
  end

  @impl true
  def handle_event("switch_on", params, socket) do
    account_id = get_in(params, ["link", "account_id"])

    case BudgetLink.switch_on(socket.assigns.current_scope, account_id) do
      {:ok, counts} ->
        {:noreply,
         socket
         |> put_flash(:info, switched_on(counts))
         |> load_link()
         |> AbakusWeb.SettingsNav.assign_groups()}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, refused(reason))}
    end
  end

  def handle_event("map_categories", params, socket) do
    mapping = Map.get(params, "mapping", %{})

    case BudgetLink.put_category_mapping(socket.assigns.current_scope, mapping) do
      {:ok, _mapping} ->
        {:noreply, socket |> put_flash(:info, "Kategorie-Zuordnung gespeichert.") |> load()}

      {:error, message} ->
        {:noreply, put_flash(socket, :error, message)}
    end
  end

  defp switched_on(counts) do
    linked =
      "Mit dem Budget verknüpft: #{bookings(counts.adopted)} übernommen, " <>
        "#{bookings(counts.created)} neu angelegt."

    case unlinked(counts) do
      [] -> linked
      unlinked -> linked <> " Unverknüpft geblieben: " <> Enum.join(unlinked, "; ") <> "."
    end
  end

  defp unlinked(%{unadoptable: unadoptable, left: left}) do
    [
      unadoptable > 0 &&
        "#{bookings(unadoptable)} mit Kasse-Kennung, die sich nicht übernehmen " <>
          "#{if unadoptable == 1, do: "ließ", else: "ließen"} (Aufteilung, Umbuchung oder doppelt) – " <>
          "bitte von Hand prüfen",
      left > 0 && "#{bookings(left)} mit Kasse-Kennung ohne passende Ausgabe"
    ]
    |> Enum.filter(& &1)
  end

  defp bookings(1), do: "1 Buchung"
  defp bookings(count), do: "#{count} Buchungen"

  defp refused(:no_account), do: "Bitte ein offenes Budget-Konto wählen."
  defp refused(:linked), do: "Die Kasse ist schon mit dem Budget verknüpft."
  defp refused(message) when is_binary(message), do: message
  defp refused(_reason), do: "Die Verknüpfung ließ sich nicht einschalten."

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.settings
      current={:kasse_budget}
      flash={@flash}
      current_scope={@current_scope}
      areas={@areas}
      area={@area}
      groups={@settings_groups}
    >
      <.header>
        Budget-Verknüpfung
        <:subtitle>Deine Anteile an geteilten Ausgaben in deinem Budget.</:subtitle>
      </.header>

      <div class="flex flex-col gap-8">
        <section aria-labelledby="budget-link" class="max-w-prose">
          <.section_heading id="budget-link">Verknüpfung</.section_heading>
          <p :if={@account} id="budget-link-state">
            Dein Anteil an jeder Ausgabe ist eine Buchung im Konto <.link
              href={~p"/budget/accounts/#{@account}"}
              class="link link-primary"
            >
              {@account.name}
            </.link>; ihr Saldo ist dein Saldo in der Kasse. Kategorie, Memo, Markierung und Bestätigung
            kannst du dort ändern. Die Kategorie setzt die Kasse neu, sobald sich die Kategorie der Ausgabe ändert.
          </p>
          <div :if={!@account} class="flex flex-col gap-3">
            <p id="budget-link-state">
              Noch nicht mit dem Budget verknüpft. Danach ist dein Anteil an jeder Ausgabe eine Buchung im
              gewählten Konto, in der Kategorie, die du unten zuordnest.
            </p>
            <p :if={@start_date} id="budget-link-ynab">
              Führe vorher den letzten YNAB-Import aus und ordne erst danach die Kategorien zu. Buchungen mit
              Kasse-Kennung in diesem Konto werden verknüpft und behalten Kategorie, Status und Bestätigung;
              jede Ausgabe seit dem {@start_date} ohne Buchung bekommt eine. Deine YNAB-Verbindung wird entfernt.
            </p>
            <p :if={!@start_date} id="budget-link-ynab">
              Jede bisherige Ausgabe bekommt eine Buchung.
            </p>
            <.form for={@link_form} id="budget-link-form" phx-submit="switch_on">
              <.input
                field={@link_form[:account_id]}
                type="select"
                label="Konto für geteilte Ausgaben"
                prompt="– Konto wählen –"
                options={@account_options}
                required
              />
              <.action_bar>
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
          </div>
        </section>

        <section aria-labelledby="budget-categories">
          <.section_heading id="budget-categories">Kategorien</.section_heading>
          <p class="mb-3 max-w-prose text-sm text-base-content/70">
            In welcher Kategorie des Budgets landet dein Anteil? Ohne Zuordnung bleibt er unkategorisiert.
          </p>
          <p
            :if={@start_date}
            id="budget-mapping-ynab"
            class="mb-3 max-w-prose text-sm text-base-content/70"
          >
            Erst nach dem letzten YNAB-Import zuordnen: Er ersetzt die Kategorien des Budgets und läuft nicht,
            solange eine Zuordnung besteht.
          </p>
          <.form for={@mapping_form} id="budget-mapping-form" phx-submit="map_categories">
            <.table id="budget-mapping" rows={@rows} row_id={&"budget-mapping-#{&1.id}"} size={:dense}>
              <:col :let={category} label="In der Kasse">
                {category.name}
                <span :if={category.archived_at} class="text-base-content/70">(archiviert)</span>
              </:col>
              <:col :let={category} label="Im Budget">
                <.input
                  field={@mapping_form["#{category.id}"]}
                  type="select"
                  label={"Kategorie im Budget für #{category.name}"}
                  hide_label
                  prompt="– unkategorisiert –"
                  options={@budget_groups}
                />
              </:col>
            </.table>
            <.action_bar>
              <.button id="budget-mapping-submit" type="submit" variant={:primary} icon="save">
                Zuordnung speichern
              </.button>
            </.action_bar>
          </.form>
        </section>
      </div>
    </Layouts.settings>
    """
  end
end
