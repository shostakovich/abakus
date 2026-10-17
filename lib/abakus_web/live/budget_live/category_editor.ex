defmodule AbakusWeb.BudgetLive.CategoryEditor do
  @moduledoc """
  Adding, renaming and deleting groups and categories, as in YNAB: "+ Gruppe" above the table, "+" on a group's row
  (or "Kategorie hinzufügen" in the group's popover, where there is no hover) and a group's name open small
  popovers; a category is renamed and deleted in its dialog (its sheet on phones). Deleting a category
  asks for the category that takes over everything, and says when reconciled transactions change too; a group is
  deleted only when it is empty.

  The popover's state is `%{kind, group, category, step, error, open, anchor, ...}`: `kind` is `:new_group`,
  `:new_category`, `:group` or `:category`, `step` is `:name` or (for a category) `:delete`. A closed popover keeps
  its state and stays rendered, so focus returns to its trigger.
  """
  use AbakusWeb, :html

  alias Abakus.Categories
  alias Abakus.Categories.{Category, CategoryGroup}

  @doc "The popover the params ask for, from the listed groups; nil when what they name is not listed."
  def open(%{"edit" => "new_group"}, _groups), do: state(:new_group, nil, nil)

  def open(%{"edit" => "new_category", "group" => id} = params, groups) do
    with %CategoryGroup{} = group <- find_group(groups, id),
         do: %{state(:new_category, group, nil) | anchor: params["anchor"]}
  end

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
    do: %{
      kind: kind,
      group: group,
      category: category,
      step: :name,
      error: nil,
      open: true,
      anchor: nil
    }

  defp find_group(groups, id), do: Enum.find(groups, &(Integer.to_string(&1.id) == id))

  @doc """
  Creates or renames as the popover says: `:ok`, the state with the name's error, or `:gone` when what it names
  was deleted meanwhile.
  """
  def save(scope, edit, name) do
    case write(scope, edit, %{name: String.trim(name)}) do
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

  defp write(scope, %{kind: :new_group}, attrs),
    do: Categories.create_category_group(scope, attrs)

  defp write(scope, %{kind: :new_category, group: group}, attrs),
    do: Categories.create_category(scope, Map.put(attrs, :category_group_id, group.id))

  defp write(scope, %{kind: :group, group: group}, attrs),
    do: Categories.update_category_group(scope, group, attrs)

  defp write(scope, %{kind: :category, category: category}, attrs),
    do: Categories.update_category(scope, category, attrs)

  @doc """
  "Löschen": deletes an empty group (`:ok`, the state with the error, or `:gone`), or for a category moves on to
  asking which category takes over (`{:ask, state}`), offering every other regular category.
  """
  def delete(scope, %{kind: :group, group: group} = edit, _groups) do
    case Categories.delete_category_group(scope, group) do
      {:ok, _group} -> :ok
      {:error, :not_empty} -> {:error, %{edit | error: "Nur leere Gruppen lassen sich löschen."}}
      {:error, _gone} -> :gone
    end
  end

  def delete(scope, %{kind: :category, category: category} = edit, groups) do
    targets =
      for group <- groups,
          options = for(c <- group.categories, c.id != category.id, do: {c.name, c.id}),
          options != [],
          do: {group.name, options}

    reconciled = Categories.reconciled_transactions?(scope, category)
    asking = %{step: :delete, error: nil, targets: targets, reconciled: reconciled, into: nil}
    {:ask, Map.merge(edit, asking)}
  end

  @doc """
  Deletes the category into the one picked among the offered; the warning shown about reconciled transactions
  counts as asking. `:ok`, `{:error, state}` to show again, or `:gone`.
  """
  def confirm_delete(scope, %{kind: :category, step: :delete} = edit, into_id, groups) do
    edit = %{edit | into: into_id, error: nil}

    with %Category{} = into <- find_target(edit, groups, into_id),
         opts = if(edit.reconciled, do: [reconciled: :confirmed], else: []),
         {:ok, _deleted} <- Categories.delete_category(scope, edit.category, into, opts) do
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
    <div class="flex shrink-0">
      <.button
        id="add-group"
        variant={:ghost}
        size={:sm}
        icon="plus"
        aria-expanded={to_string(open?(@edit))}
        phx-click="edit_open"
        phx-value-edit="new_group"
      >
        Gruppe
      </.button>
      <.editor :if={@edit} edit={@edit} align_end />
    </div>
    """
  end

  attr :edit, :map, required: true

  attr :align_end, :boolean,
    default: false,
    doc: "aligns the popover to the right edge of what opened it"

  @doc "The popover of a group: a name to add or rename it, or to add a category."
  def editor(assigns) do
    ~H"""
    <.popover
      id="edit-pop"
      title={title(@edit)}
      anchor={anchor(@edit)}
      align={if @align_end, do: :end, else: :start}
      show={@edit.open}
      on_cancel={JS.push("edit_close")}
    >
      <.name_form edit={@edit} />
    </.popover>
    """
  end

  @doc "Whether the popover's state is there and open."
  def open?(%{open: open}), do: open
  def open?(_edit), do: false

  defp anchor(%{anchor: anchor}) when is_binary(anchor), do: anchor
  defp anchor(%{kind: :new_group}), do: "add-group"
  defp anchor(%{kind: :new_category, group: group}), do: "add-category-#{group.id}"
  defp anchor(%{kind: :group, group: group}), do: "edit-group-#{group.id}"

  defp title(%{kind: :new_group}), do: "Neue Kategoriegruppe"
  defp title(%{kind: :new_category, group: group}), do: "Neue Kategorie in #{group.name}"
  defp title(%{kind: :group}), do: "Kategoriegruppe"

  attr :edit, :map, required: true

  defp name_form(assigns) do
    ~H"""
    <form id="edit-form" phx-submit="edit_save" novalidate>
      <.input
        id="edit-name"
        name="name"
        label="Name"
        hide_label
        value={name(@edit)}
        placeholder="Name"
        autocomplete="off"
        required
        errors={List.wrap(@edit.error)}
        help={
          (@edit.kind == :group and not @edit.deletable) && "Nur leere Gruppen lassen sich löschen."
        }
        autofocus
      />
      <div class="mt-3 flex justify-end gap-2">
        <.button size={:sm} phx-click="edit_close">Abbrechen</.button>
        <.button type="submit" variant={:primary} size={:sm}>
          {if @edit.kind == :group, do: "Speichern", else: "Anlegen"}
        </.button>
      </div>
      <div
        :if={@edit.kind == :group}
        class="-mx-4 mt-4 flex flex-wrap gap-2 border-t border-base-content/10 px-2 pt-2"
      >
        <.button
          id="edit-add-category"
          variant={:ghost}
          size={:sm}
          icon="plus"
          phx-click="edit_open"
          phx-value-edit="new_category"
          phx-value-group={@edit.group.id}
          phx-value-anchor={"edit-group-#{@edit.group.id}"}
        >
          Kategorie hinzufügen
        </.button>
        <.button
          :if={@edit.deletable}
          id="edit-delete"
          variant={:ghost}
          size={:sm}
          icon="trash-2"
          confirm={"Gruppe „#{@edit.group.name}“ löschen?"}
          phx-click="delete_group"
          phx-value-group={@edit.group.id}
        >
          Gruppe löschen
        </.button>
      </div>
    </form>
    """
  end

  defp name(%{kind: :group, group: group}), do: group.name
  defp name(_new), do: nil

  attr :edit, :map, required: true, doc: "the category's state, from `open/2`"
  attr :autofocus, :boolean, default: false

  @doc "A category's name in its dialog, renamed in place: Enter and leaving the field save, Escape puts it back."
  def category_name(assigns) do
    ~H"""
    <section id="category-name">
      <.section_heading level={3}>Name</.section_heading>
      <form id="category-name-form" phx-submit="edit_save" novalidate>
        <.input
          id="category-name-input"
          name="name"
          label="Name"
          hide_label
          value={@edit.category.name}
          autocomplete="off"
          required
          errors={if @edit.step == :name, do: List.wrap(@edit.error), else: []}
          autofocus={@autofocus}
          phx-blur="edit_save"
          phx-hook="RenameField"
          data-saved={@edit.category.name}
        />
      </form>
    </section>
    """
  end

  attr :edit, :map, required: true, doc: "the category's state, from `open/2`"

  @doc "Deleting a category in its dialog: which category takes over everything, then a confirmation."
  def category_delete(assigns) do
    ~H"""
    <section id="category-delete" class="border-t border-base-content/10 pt-4">
      <.button
        :if={@edit.step == :name}
        id="edit-delete"
        variant={:ghost}
        size={:sm}
        icon="trash-2"
        class="-ms-3 text-error-ink"
        phx-click="edit_delete"
      >
        Kategorie löschen
      </.button>
      <form
        :if={@edit.step == :delete}
        id="delete-form"
        phx-change="edit_delete_change"
        phx-submit="edit_confirm_delete"
        novalidate
      >
        <%= if @edit.targets == [] do %>
          <p class="text-sm">Es gibt keine andere Kategorie, die alles übernehmen kann.</p>
        <% else %>
          <.combobox
            id="delete-into"
            name="into"
            label="Buchungen, Zuweisungen und Geld gehen in"
            placeholder="Kategorie suchen"
            options={@edit.targets}
            value={@edit.into}
            required
            errors={List.wrap(@edit.error)}
            help={@edit.reconciled && "Auch abgeglichene Buchungen bekommen die neue Kategorie."}
            help_tone={if @edit.reconciled, do: :warning}
          />
        <% end %>
        <div class="mt-3 flex justify-end gap-2">
          <.button size={:sm} phx-click="edit_back">Abbrechen</.button>
          <.button
            :if={@edit.targets != []}
            id="delete-submit"
            type="submit"
            variant={:danger}
            size={:sm}
            confirm={"Kategorie „#{@edit.category.name}“ löschen?"}
            confirm_text="Buchungen, Zuweisungen und Geld gehen in die gewählte Kategorie."
          >
            Löschen
          </.button>
        </div>
      </form>
    </section>
    """
  end
end
