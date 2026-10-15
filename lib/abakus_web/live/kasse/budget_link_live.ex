defmodule AbakusWeb.Kasse.BudgetLinkLive do
  @moduledoc """
  "Budget", the budget owner's link between the Kasse and the budget: where their shares are booked and which
  budget category each Kasse category's shares land in. Anyone else gets 404.
  """
  use AbakusWeb, :kasse_live_view

  alias Abakus.Categories
  alias Abakus.Kasse.BudgetLink
  alias Abakus.Kasse.Categories, as: KasseCategories

  @impl true
  def mount(_params, _session, socket) do
    if !socket.assigns.current_scope.user.budget_owner, do: raise(AbakusWeb.NotFoundError)

    {:ok,
     socket
     |> assign(
       page_title: "Budget",
       account: BudgetLink.account(socket.assigns.current_participant),
       budget_groups: budget_groups()
     )
     |> load()}
  end

  defp budget_groups do
    for %{categories: [_ | _] = categories} = group <- Categories.list_category_groups(),
        do: {group.name, Enum.map(categories, &{&1.name, &1.id})}
  end

  defp load(socket) do
    mapping = BudgetLink.category_mapping()

    rows =
      for category <- KasseCategories.list_categories(:all),
          is_nil(category.archived_at) or Map.has_key?(mapping, category.id),
          do: category

    assign(socket,
      rows: rows,
      mapping_form: to_form(Map.new(rows, &{"#{&1.id}", mapping[&1.id] || ""}), as: :mapping)
    )
  end

  @impl true
  def handle_event("map_categories", params, socket) do
    case BudgetLink.put_category_mapping(Map.get(params, "mapping", %{})) do
      {:ok, _mapping} ->
        {:noreply, socket |> put_flash(:info, "Kategorie-Zuordnung gespeichert.") |> load()}

      {:error, message} ->
        {:noreply, put_flash(socket, :error, message)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.kasse
      flash={@flash}
      current_scope={@current_scope}
      areas={@areas}
      area={@area}
      account_groups={@account_groups}
      account_dialog={@account_dialog}
      current={:settings}
    >
      <.header back={~p"/kasse/settings"} back_label="Gruppe">
        Budget
        <:subtitle>Deine Anteile an geteilten Ausgaben in deinem Budget.</:subtitle>
      </.header>

      <div class="flex flex-col gap-8">
        <section aria-labelledby="budget-link" class="max-w-prose">
          <.section_heading id="budget-link">Verknüpfung</.section_heading>
          <p :if={@account} id="budget-link-state">
            Dein Anteil an jeder Ausgabe ist eine Buchung im Konto <.link
              navigate={~p"/budget/accounts/#{@account}"}
              class="link link-primary"
            >
              {@account.name}
            </.link>; ihr Saldo ist dein Saldo in der Kasse. Kategorie, Memo, Markierung und Bestätigung
            kannst du dort ändern. Die Kategorie setzt die Kasse neu, sobald sich die Kategorie der Ausgabe ändert.
          </p>
          <p :if={!@account} id="budget-link-state">
            Noch nicht mit dem Budget verknüpft.
          </p>
        </section>

        <section aria-labelledby="budget-categories">
          <.section_heading id="budget-categories">Kategorien</.section_heading>
          <p class="mb-3 max-w-prose text-sm text-base-content/70">
            In welcher Kategorie des Budgets landet dein Anteil? Ohne Zuordnung bleibt er unkategorisiert.
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
    </Layouts.kasse>
    """
  end
end
