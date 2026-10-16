defmodule AbakusWeb.Kasse.CategoriesLive do
  @moduledoc """
  The categories in their order with their number of expenses: rename, move up and down,
  archive, bring back, add (before "Sonstiges").
  """
  use AbakusWeb, :kasse_live_view

  alias Abakus.Kasse.{Categories, Expenses}
  alias Abakus.Kasse.Categories.Category
  alias AbakusWeb.Kasse.CategoryIcon

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(page_title: "Kategorien", renaming: nil)
     |> assign_new_form(Categories.change_category(%Category{}))
     |> load()}
  end

  defp load(socket) do
    counts = Expenses.count_by_category(socket.assigns.current_scope)

    {archived, active} =
      Categories.list_categories(socket.assigns.current_scope, :all)
      |> Enum.map(&%{category: &1, expenses: Map.get(counts, &1.id, 0)})
      |> Enum.split_with(&Category.archived?(&1.category))

    assign(socket, active: active, archived: archived, last: length(active) - 1)
  end

  defp assign_new_form(socket, changeset),
    do: assign(socket, new_form: to_form(changeset, as: :category))

  defp assign_rename_form(socket, changeset),
    do: assign(socket, rename_form: to_form(changeset, as: :rename))

  @impl true
  def handle_event("validate_new", %{"category" => params}, socket) do
    changeset = Categories.change_category(%Category{}, params)
    {:noreply, assign_new_form(socket, Map.put(changeset, :action, :validate))}
  end

  def handle_event("create", %{"category" => params}, socket) do
    case Categories.create_category(socket.assigns.current_scope, params) do
      {:ok, category} ->
        {:noreply,
         socket
         |> put_flash(:info, "Kategorie „#{category.name}“ hinzugefügt.")
         |> assign_new_form(Categories.change_category(%Category{}))
         |> load()}

      {:error, changeset} ->
        {:noreply, assign_new_form(socket, changeset)}
    end
  end

  def handle_event("rename", %{"id" => id}, socket) do
    with_category(socket, id, fn category ->
      socket
      |> assign(renaming: category)
      |> assign_rename_form(Categories.change_category(category))
    end)
  end

  def handle_event("cancel_rename", _params, socket),
    do: {:noreply, assign(socket, renaming: nil)}

  def handle_event("validate_rename", %{"rename" => params}, socket) do
    changeset = Categories.change_category(socket.assigns.renaming, params)
    {:noreply, assign_rename_form(socket, Map.put(changeset, :action, :validate))}
  end

  def handle_event("save_rename", %{"rename" => params}, socket) do
    %{current_scope: scope, renaming: category} = socket.assigns

    case Categories.rename_category(scope, category, params) do
      {:ok, _renamed} ->
        {:noreply, socket |> put_flash(:info, "Gespeichert.") |> assign(renaming: nil) |> load()}

      {:error, changeset} ->
        {:noreply, assign_rename_form(socket, changeset)}
    end
  end

  def handle_event("move", %{"id" => id, "direction" => direction}, socket)
      when direction in ["up", "down"] do
    with_category(socket, id, fn category ->
      scope = socket.assigns.current_scope

      case Categories.move_category(scope, category, String.to_existing_atom(direction)) do
        {:ok, _category} -> load(socket)
        {:error, :not_found} -> socket |> put_flash(:error, "Kategorie nicht gefunden.") |> load()
      end
    end)
  end

  def handle_event("archive", %{"id" => id}, socket) do
    with_category(socket, id, fn category ->
      {:ok, category} = Categories.archive_category(socket.assigns.current_scope, category)

      socket |> put_flash(:info, "Kategorie „#{category.name}“ archiviert.") |> load()
    end)
  end

  def handle_event("reactivate", %{"id" => id}, socket) do
    with_category(socket, id, fn category ->
      {:ok, category} = Categories.reactivate_category(socket.assigns.current_scope, category)

      socket |> put_flash(:info, "Kategorie „#{category.name}“ reaktiviert.") |> load()
    end)
  end

  defp with_category(socket, id, fun) do
    case Categories.get_category(socket.assigns.current_scope, id) do
      %Category{} = category -> {:noreply, fun.(category)}
      nil -> {:noreply, socket |> put_flash(:error, "Kategorie nicht gefunden.") |> load()}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.settings
      current={:kasse_categories}
      flash={@flash}
      current_scope={@current_scope}
      areas={@areas}
      area={@area}
      groups={@settings_groups}
    >
      <.header>
        Kategorien
        <:subtitle>
          Umbenennen, sortieren oder archivieren. Archivierte Kategorien stehen bei neuen Ausgaben nicht mehr zur Wahl.
        </:subtitle>
      </.header>

      <div class="flex flex-col gap-8">
        <.list id="categories">
          <.list_row
            :for={{row, index} <- Enum.with_index(@active)}
            id={"category-#{row.category.id}"}
            title={row.category.name}
            menu={:always}
          >
            <:leading>
              <.plush name={CategoryIcon.for_category(row.category.name)} size={:lg} />
            </:leading>
            <:meta>{expense_count(row.expenses)}</:meta>
            <:action
              id={"category-#{row.category.id}-up"}
              label="Nach oben"
              icon="chevron-up"
              inline
              disabled={index == 0}
              on_click={JS.push("move", value: %{id: row.category.id, direction: "up"})}
            />
            <:action
              id={"category-#{row.category.id}-down"}
              label="Nach unten"
              icon="chevron-down"
              inline
              disabled={index == @last}
              on_click={JS.push("move", value: %{id: row.category.id, direction: "down"})}
            />
            <:action
              id={"category-#{row.category.id}-rename"}
              label="Umbenennen"
              icon="pencil"
              on_click={JS.push("rename", value: %{id: row.category.id})}
            />
            <:action
              id={"category-#{row.category.id}-archive"}
              label="Archivieren"
              icon="archive"
              on_click={JS.push("archive", value: %{id: row.category.id})}
            />
          </.list_row>
        </.list>

        <section aria-labelledby="categories-new">
          <.section_heading id="categories-new">Kategorie hinzufügen</.section_heading>
          <.form for={@new_form} id="category-form" phx-change="validate_new" phx-submit="create">
            <.input
              field={@new_form[:name]}
              label="Name"
              placeholder="Name"
              required
              maxlength={Abakus.Kasse.Names.max_length()}
              autocomplete="off"
              phx-patch-focused
              inline
            >
              <.button type="submit" variant={:primary} icon="plus" class="join-item">
                Hinzufügen
              </.button>
            </.input>
          </.form>
        </section>

        <section :if={@archived != []} aria-labelledby="categories-archived">
          <.section_heading id="categories-archived" count={length(@archived)}>
            Archiviert
          </.section_heading>
          <.list id="categories-archived-list">
            <.list_row
              :for={row <- @archived}
              id={"category-#{row.category.id}"}
              title={row.category.name}
            >
              <:leading>
                <.plush name={CategoryIcon.for_category(row.category.name)} size={:lg} />
              </:leading>
              <:meta>{expense_count(row.expenses)}</:meta>
              <:trailing>
                <.button
                  id={"category-#{row.category.id}-reactivate"}
                  size={:sm}
                  icon="undo-2"
                  phx-click={JS.push("reactivate", value: %{id: row.category.id})}
                >
                  Zurückholen
                </.button>
              </:trailing>
            </.list_row>
          </.list>
        </section>
      </div>

      <.rename_popover
        :if={@renaming}
        id={"rename-#{@renaming.id}"}
        name={@renaming.name}
        anchor={"category-#{@renaming.id}"}
        form={@rename_form}
      />
    </Layouts.settings>
    """
  end
end
