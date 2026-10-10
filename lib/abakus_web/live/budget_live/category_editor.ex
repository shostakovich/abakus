defmodule AbakusWeb.BudgetLive.CategoryEditor do
  @moduledoc """
  Adding, renaming and deleting groups and categories in small popovers, as in YNAB: "+ Gruppe" above the table,
  "+" on a group's row, a group's name or the pencil in a category's inspector to rename or delete. Deleting a category
  asks for the category that takes over everything, and says when reconciled transactions change too; a group is
  deleted only when it is empty.

  The popover's state is `%{kind, group, category, step, error, ...}`: `kind` is `:new_group`, `:new_category`,
  `:group` or `:category`, `step` is `:name` or (for a category) `:delete`.
  """
  use AbakusWeb, :html

  alias Abakus.Categories
  alias Abakus.Categories.{Category, CategoryGroup}

  @doc "The popover the params ask for, from the listed groups; nil when what they name is not listed."
  def open(%{"edit" => "new_group"}, _groups), do: state(:new_group, nil, nil)

  def open(%{"edit" => "new_category", "group" => id}, groups),
    do:
      with(
        %CategoryGroup{} = group <- find_group(groups, id),
        do: state(:new_category, group, nil)
      )

  def open(%{"edit" => "group", "group" => id}, groups) do
    with %CategoryGroup{} = group <- find_group(groups, id),
         do: Map.put(state(:group, group, nil), :deletable, group.categories == [])
  end

  def open(%{"edit" => "category", "category" => id}, groups) do
    Enum.find_value(groups, fn group ->
      category = Enum.find(group.categories, &(Integer.to_string(&1.id) == id))
      category && state(:category, group, category)
    end)
  end

  def open(_params, _groups), do: nil

  defp state(kind, group, category),
    do: %{kind: kind, group: group, category: category, step: :name, error: nil}

  defp find_group(groups, id), do: Enum.find(groups, &(Integer.to_string(&1.id) == id))

  @doc """
  Creates or renames as the popover says: `:ok`, the state with the name's error, or `:gone` when what it names
  was deleted meanwhile.
  """
  def save(edit, name) do
    case write(edit, %{name: name}) do
      {:ok, _saved} -> :ok
      {:error, changeset} -> name_error(edit, changeset)
    end
  end

  defp name_error(edit, changeset) do
    case Keyword.get_values(changeset.errors, :name) do
      [] ->
        :gone

      errors ->
        {:error, %{edit | error: "Name " <> Enum.map_join(errors, ", ", &translate_error/1)}}
    end
  end

  defp write(%{kind: :new_group}, attrs), do: Categories.create_category_group(attrs)

  defp write(%{kind: :new_category, group: group}, attrs),
    do: Categories.create_category(Map.put(attrs, :category_group_id, group.id))

  defp write(%{kind: :group, group: group}, attrs),
    do: Categories.update_category_group(group, attrs)

  defp write(%{kind: :category, category: category}, attrs),
    do: Categories.update_category(category, attrs)

  @doc """
  "Löschen": deletes an empty group (`:ok`, the state with the error, or `:gone`), or for a category moves on to
  asking which category takes over (`{:ask, state}`), offering every other regular category.
  """
  def delete(%{kind: :group, group: group} = edit, _groups) do
    case Categories.delete_category_group(group) do
      {:ok, _group} -> :ok
      {:error, :not_empty} -> {:error, %{edit | error: "Nur leere Gruppen lassen sich löschen."}}
      {:error, _gone} -> :gone
    end
  end

  def delete(%{kind: :category, category: category} = edit, groups) do
    targets =
      for group <- groups,
          options = for(c <- group.categories, c.id != category.id, do: {c.name, c.id}),
          options != [],
          do: {group.name, options}

    reconciled = Categories.reconciled_transactions?(category)
    {:ask, Map.merge(edit, %{step: :delete, targets: targets, reconciled: reconciled, into: nil})}
  end

  @doc """
  Deletes the category into the one picked among the offered; the warning shown about reconciled transactions
  counts as asking. `:ok`, `{:error, state}` to show again, or `:gone`.
  """
  def confirm_delete(%{kind: :category, step: :delete} = edit, into_id, groups) do
    edit = %{edit | into: into_id, error: nil}

    with %Category{} = into <- find_target(edit, groups, into_id),
         opts = if(edit.reconciled, do: [reconciled: :confirmed], else: []),
         {:ok, _deleted} <- Categories.delete_category(edit.category, into, opts) do
      :ok
    else
      nil ->
        {:error, %{edit | error: "Bitte eine Kategorie wählen."}}

      {:error, :reconciled} ->
        {:error, %{edit | reconciled: true}}

      {:error, %Ecto.Changeset{}} ->
        {:error, %{edit | error: "Zusammen sind die Zuweisungen zu groß."}}

      {:error, _gone} ->
        :gone
    end
  end

  defp find_target(edit, groups, id) do
    offered = for {_group, options} <- edit.targets, {_name, id} <- options, do: id

    groups
    |> Enum.flat_map(& &1.categories)
    |> Enum.find(&(Integer.to_string(&1.id) == id and &1.id in offered))
  end

  attr :edit, :map,
    default: nil,
    doc: "the popover's state, when it is the one for adding a group"

  @doc "\"+ Gruppe\" above the table."
  def add_group(assigns) do
    ~H"""
    <div class="dropdown">
      <button
        id="add-group"
        type="button"
        class="btn btn-sm btn-link px-0 text-decoration-none d-inline-flex align-items-center gap-1"
        aria-expanded={to_string(@edit != nil)}
        phx-click="edit_open"
        phx-value-edit="new_group"
      >
        <.icon name="plus" class="app-icon-sm" />Gruppe
      </button>
      <.popover :if={@edit} edit={@edit} />
    </div>
    """
  end

  attr :edit, :map, required: true

  attr :align_end, :boolean,
    default: false,
    doc: "aligns the popover to the right edge of what opened it"

  @doc "The popover: a name to add or rename, or which category takes over a deleted one."
  def popover(assigns) do
    ~H"""
    <div
      id="edit-pop"
      class={["dropdown-menu show p-3 app-edit-menu", @align_end && "dropdown-menu-end"]}
      data-bs-popper="static"
      role="dialog"
      aria-labelledby="edit-title"
      phx-click-away="edit_close"
      phx-window-keydown="edit_close"
      phx-key="Escape"
    >
      <div id="edit-title" class="fw-semibold mb-2 text-truncate">{title(@edit)}</div>
      <.name_form :if={@edit.step == :name} edit={@edit} />
      <.delete_form :if={@edit.step == :delete} edit={@edit} />
    </div>
    """
  end

  defp title(%{kind: :new_group}), do: "Neue Kategoriegruppe"
  defp title(%{kind: :new_category, group: group}), do: "Neue Kategorie in #{group.name}"
  defp title(%{kind: :group}), do: "Kategoriegruppe"
  defp title(%{kind: :category, step: :name}), do: "Kategorie"
  defp title(%{kind: :category, category: category}), do: "„#{category.name}“ löschen"

  attr :edit, :map, required: true

  defp name_form(assigns) do
    assigns = assign(assigns, :value, name(assigns.edit))

    ~H"""
    <form id="edit-form" phx-submit="edit_save" novalidate>
      <input
        id="edit-name"
        name="name"
        type="text"
        value={@value}
        autocomplete="off"
        required
        aria-label="Name"
        placeholder="Name"
        class={["form-control form-control-sm", @edit.error && "is-invalid"]}
        aria-describedby={@edit.error && "edit-error"}
        phx-mounted={JS.focus()}
      />
      <div :if={@edit.error} id="edit-error" class="invalid-feedback d-block">{@edit.error}</div>
      <p
        :if={@edit.kind == :group and not @edit.deletable}
        class="small text-body-secondary mt-2 mb-0"
      >
        Nur leere Gruppen lassen sich löschen.
      </p>
      <div class="d-flex gap-2 mt-3">
        <button
          :if={@edit.kind == :category or (@edit.kind == :group and @edit.deletable)}
          id="edit-delete"
          type="button"
          class="btn btn-sm btn-outline-danger me-auto"
          phx-click="edit_delete"
        >
          Löschen
        </button>
        <button type="button" class="btn btn-sm btn-light ms-auto" phx-click="edit_close">
          Abbrechen
        </button>
        <button type="submit" class="btn btn-sm btn-primary">
          {if @edit.kind in [:new_group, :new_category], do: "Anlegen", else: "Speichern"}
        </button>
      </div>
    </form>
    """
  end

  defp name(%{kind: :group, group: group}), do: group.name
  defp name(%{kind: :category, category: category}), do: category.name
  defp name(_new), do: nil

  attr :edit, :map, required: true

  defp delete_form(assigns) do
    ~H"""
    <form id="delete-form" phx-submit="edit_confirm_delete" novalidate>
      <%= if @edit.targets == [] do %>
        <p class="mb-0">Es gibt keine andere Kategorie, die alles übernehmen kann.</p>
      <% else %>
        <label for="delete-into" class="form-label small">
          Buchungen, Zuweisungen und Geld gehen in
        </label>
        <select
          id="delete-into"
          name="into"
          required
          class={["form-select form-select-sm", @edit.error && "is-invalid"]}
        >
          <option value="">Kategorie wählen …</option>
          {Phoenix.HTML.Form.options_for_select(@edit.targets, @edit.into)}
        </select>
        <div :if={@edit.error} class="invalid-feedback d-block">{@edit.error}</div>
        <p :if={@edit.reconciled} id="delete-reconciled" class="small text-warning-emphasis mt-2 mb-0">
          Auch abgeglichene Buchungen bekommen die neue Kategorie.
        </p>
      <% end %>
      <div class="d-flex gap-2 mt-3">
        <button type="button" class="btn btn-sm btn-light ms-auto" phx-click="edit_close">
          Abbrechen
        </button>
        <button :if={@edit.targets != []} type="submit" class="btn btn-sm btn-danger">
          Löschen
        </button>
      </div>
    </form>
    """
  end
end
