defmodule AbakusWeb.BudgetLive do
  @moduledoc """
  The budget, months side by side as in YNAB 4 and Actual. The first month comes from the URL (`month`). How many
  months fit, the `BudgetLayout` hook measures in the browser (`assets/js/hooks/budget.js`); the browser also gives
  the current month, so that it is the user's own. Every month takes assignments, as in YNAB; Zu verteilen may go
  below zero.

  As in Actual there is no inspector: a month's head shows how Zu verteilen adds up and its Verteilen menu
  fills the underfunded or resets the month; a category's name or pencil opens its dialog (`Inspector`: name,
  target, deleting), on phones a sheet that also takes the assignment. Targets, snoozing and covering work in the
  focus month; an overspent Verfügbar opens the popover that covers it (`Popover`), which makes its month the
  focus. Covering, filling and a target's Zuweisen offer "Rückgängig" in a toast until the next action. Money moves
  between categories by changing their assignments. Groups are added, renamed and deleted in
  popovers (`CategoryEditor`): "+ Gruppe" above the table (below it on phones), "+" and the name on a group's row.
  With a mouse, categories and groups are dragged into a new order (`Sortable`: `sort_category`, `sort_group`).
  """
  use AbakusWeb, :live_view

  alias Abakus.{Budget, Categories, Format, LocalTime, Money, Names}

  alias AbakusWeb.BudgetLive.{
    CategoryEditor,
    Components,
    Inspector,
    Popover,
    Rows,
    Status,
    TargetForm,
    Window
  }

  on_mount {AbakusWeb.AccountGroups, {:pass_on, [:synced]}}

  @fit %{months: 1, span: 7, compact: false}

  @impl true
  def render(assigns) do
    assigns =
      assign(
        assigns,
        :open,
        assigns.inspector.selected != nil and match?(%{kind: :category}, assigns.editing)
      )

    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      areas={@areas}
      area={@area}
      current={:budget}
      width={:full}
      account_groups={@account_groups}
      depot_sidebar={@depot_sidebar}
      expiring_consents={@expiring_consents}
      account_dialog={@account_dialog}
    >
      <h1 class="sr-only">Budget</h1>
      <div
        id="budget"
        phx-hook="BudgetLayout"
        data-fit={"#{@fit.months},#{@fit.span},#{@fit.compact}"}
      >
        <div :if={not @fit.compact} class="app-toolbar">
          <Components.month_strip window={@window} />
        </div>
        <Components.month_bar
          :if={@fit.compact}
          month={focus_month(@months, @window)}
          window={@window}
        />
        <div class="app-budget-wrap">
          <table
            id="budget-table"
            phx-hook="Setzkasten.Components.Data.Sortable"
            data-sort-event="sort_category"
            data-months={length(@months)}
            class={[
              "app-budget",
              @fit.compact && "is-compact",
              length(@months) == 1 && "is-single"
            ]}
          >
            <colgroup>
              <col class="app-col-cat" />
              <%= for _month <- @months do %>
                <col class="app-col-assigned" /><col class="app-col-activity" /><col class="app-col-available" />
              <% end %>
            </colgroup>
            <thead>
              <tr :if={not @fit.compact} class="app-heads-month">
                <th class="app-cat" rowspan="2" scope="col">
                  <div class="app-cathead">
                    <span class="app-colh">Kategorie</span>
                    <CategoryEditor.add_group edit={edit_for(@editing, :new_group)} />
                  </div>
                </th>
                <th :for={month <- @months} colspan="3" class={["app-ms", month.closed && "app-past"]}>
                  <Components.month_head
                    month={month}
                    focus={month.month == @window.focus}
                    current={@current}
                  />
                </th>
              </tr>
              <tr class="app-heads">
                <th :if={@fit.compact} class="app-cat" scope="col">
                  <span class="app-colh">Kategorie</span>
                </th>
                <Components.column_heads :for={month <- @months} month={month} />
              </tr>
            </thead>
            <tbody :if={@rows.uncategorised}>
              <Components.category_row
                id="uncategorised"
                name="Nicht kategorisiert"
                cells={@rows.uncategorised.cells}
                months={@window.months}
                focus={@window.focus}
                current={@current}
                invalid={@invalid}
                assignable={false}
                compact={@fit.compact}
                budgeting={@budgeting}
              />
            </tbody>
            <Components.group
              :for={%{group: group, categories: categories, totals: totals} <- @rows.groups}
              id={"group-#{group.id}"}
              name={group.name}
              months={@window.months}
              current={@current}
              totals={totals}
              group_id={group.id}
              edit={edit_for(@editing, :group, group.id)}
            >
              <Components.category_row
                :for={%{category: category, cells: cells} <- categories}
                id={category.id}
                name={category.name}
                cells={cells}
                months={@window.months}
                focus={@window.focus}
                current={@current}
                invalid={@invalid}
                compact={@fit.compact}
                budgeting={@budgeting}
                group_id={group.id}
              />
            </Components.group>
            <tbody :if={@rows.groups == [] and is_nil(@rows.uncategorised)}>
              <tr>
                <td colspan={1 + 3 * length(@months)} class="app-empty">
                  <.empty_state
                    id="budget-empty"
                    plush="wallet"
                    icon="wallet"
                    title="Noch keine Kategorien"
                  >
                    Lege eine Gruppe an und darin die Kategorien, auf die du dein Geld verteilst.
                    <:action>
                      <.button icon="plus" phx-click="edit_open" phx-value-edit="new_group">
                        Gruppe anlegen
                      </.button>
                    </:action>
                  </.empty_state>
                </td>
              </tr>
            </tbody>
          </table>
          <div :if={@fit.compact} class="app-add-end">
            <CategoryEditor.add_group edit={edit_for(@editing, :new_group)} />
          </div>
        </div>
      </div>
      <.modal
        :if={not @fit.compact}
        id="category-dialog"
        show={@open}
        on_cancel={JS.push("deselect")}
        class="app-dialog"
      >
        <:heading :if={@open}>
          <CategoryEditor.category_name id="category-dialog-title" edit={@editing} />
        </:heading>
        <Inspector.dialog
          :if={@open}
          inspector={@inspector}
          current={@current}
          target_form={@target_form}
          edit={@editing}
        />
      </.modal>
      <.modal
        :if={@fit.compact}
        id="panel"
        placement={:end}
        show={@open}
        on_cancel={JS.push("deselect")}
        class="app-panel"
      >
        <:heading :if={@open}>
          <CategoryEditor.category_name id="panel-title" edit={@editing} />
        </:heading>
        <Inspector.sheet
          :if={@open}
          inspector={@inspector}
          current={@current}
          target_form={@target_form}
          assign={panel_assign(@invalid, @inspector)}
          edit={@editing}
        />
      </.modal>
      <Popover.editor :if={@popover} popover={@popover} inspector={@inspector} />
    </Layouts.app>
    """
  end

  defp focus_month(months, window), do: Enum.find(months, &(&1.month == window.focus))

  defp panel_assign(
         {id, month, typed, error},
         %Inspector{selected: %{category: %{id: id}, cell: %{month: month}}}
       ),
       do: %{value: typed, error: error}

  defp panel_assign(_invalid, %Inspector{selected: %{cell: cell}}),
    do: %{value: Money.amount(cell.assigned), error: nil}

  defp panel_assign(_invalid, _inspector), do: nil

  @impl true
  def mount(_params, _session, socket) do
    connect = get_connect_params(socket) || %{}

    {:ok,
     socket
     |> assign(
       page_title: "Budget",
       current: Date.beginning_of_month(LocalTime.today()),
       fit: fit(connect["fit"]),
       focus: nil,
       invalid: nil,
       selected: nil,
       popover: nil,
       target_form: nil,
       editing: nil,
       undo: nil
     )
     |> assign_budget()}
  end

  @impl true
  def handle_info({:synced, _device}, socket),
    do: {:noreply, socket |> assign_budget() |> assign_view()}

  @impl true
  def handle_params(params, _uri, socket) do
    requested =
      case Window.parse_param(params["month"]) do
        {:ok, month} -> month
        :error -> socket.assigns.current
      end

    {:noreply, socket |> assign(:requested, requested) |> assign_view()}
  end

  @impl true
  def handle_event("fit", params, socket) do
    {:noreply, socket |> assign(:fit, fit(params)) |> assign_view()}
  end

  def handle_event("focus", %{"month" => param}, socket),
    do: {:noreply, focus_shown(socket, param)}

  def handle_event("show_month", %{"month" => param}, socket) do
    case Window.parse_param(param) do
      {:ok, month} ->
        socket = assign(socket, :focus, month)

        if month in socket.assigns.window.months,
          do: {:noreply, assign_view(socket)},
          else: {:noreply, push_patch(socket, to: Components.budget_path(month))}

      :error ->
        {:noreply, socket}
    end
  end

  def handle_event("step", %{"by" => by}, socket) when by in ["-1", "1"] do
    by = String.to_integer(by)
    %Window{first: first, focus: focus} = socket.assigns.window

    {:noreply,
     socket
     |> assign(:focus, Date.shift(focus, month: by))
     |> push_patch(to: Components.budget_path(Date.shift(first, month: by)))}
  end

  def handle_event("assign", %{"category" => id, "month" => param, "value" => value}, socket) do
    with %Categories.Category{} = category <- find_category(socket.assigns.groups, id),
         {:ok, month} <- shown_month(socket, param) do
      {:noreply, assign_amount(socket, category, month, value)}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("assign_cancel", %{"category" => id, "month" => param}, socket) do
    case Window.parse_param(param) do
      {:ok, month} -> {:noreply, clear_invalid(socket, %{id: id}, month)}
      :error -> {:noreply, socket}
    end
  end

  def handle_event("select", %{"category" => id}, socket),
    do: {:noreply, select(socket, id)}

  def handle_event("deselect", _params, socket) do
    {:noreply, socket |> assign(selected: nil, target_form: nil, editing: nil) |> assign_view()}
  end

  def handle_event("open_popover", %{"category" => id} = params, socket) do
    socket = focus_shown(socket, params["month"])

    case entry(socket, id) do
      %{cell: %{available: available}} = entry when available < 0 ->
        {:noreply, assign(socket, :popover, Popover.open(params["anchor"], entry))}

      _other ->
        {:noreply, socket}
    end
  end

  # A click away from one popover may come after the click that opened the next.
  def handle_event("close_popover", %{"anchor" => anchor}, socket) do
    case socket.assigns.popover do
      %{anchor: ^anchor} -> {:noreply, assign(socket, :popover, nil)}
      _other -> {:noreply, socket}
    end
  end

  def handle_event("close_popover", _params, socket),
    do: {:noreply, assign(socket, :popover, closed(socket.assigns.popover))}

  def handle_event("cover", %{"category" => id, "from" => from}, socket) do
    with %{} = entry <- entry(socket, id),
         {source, available} <- cover_source(socket.assigns.inspector, from, entry),
         amount when amount > 0 <- Popover.cover_amount(entry, available) do
      move(socket, source, entry.category, amount, fn _moved ->
        "#{Money.euros(amount)} aus #{name(source)} gedeckt."
      end)
    else
      _ -> {:noreply, put_flash(socket, :error, "Daraus lässt sich nichts decken.")}
    end
  end

  def handle_event("auto", %{"kind" => kind, "month" => param}, socket)
      when kind in ["underfunded", "reset"] do
    case shown_month(socket, param) do
      {:ok, month} -> {:noreply, socket |> assign(:focus, month) |> auto(kind, month)}
      :error -> {:noreply, socket}
    end
  end

  def handle_event("assign_rest", _params, socket) do
    %{selected: entry, free: free} = socket.assigns.inspector

    case entry && Status.to_assign(entry.cell, free) do
      amount when is_integer(amount) and amount > 0 ->
        move(socket, :ready_to_assign, entry.category, amount, fn _moved ->
          "#{Money.euros(amount)} #{name(entry.category)} zugewiesen."
        end)

      _nothing ->
        {:noreply, socket}
    end
  end

  def handle_event("undo", %{"id" => id}, %{assigns: %{undo: %{id: id} = undo}} = socket) do
    socket = assign(socket, :undo, nil)

    case Categories.undo_assigned(socket.assigns.current_scope, undo.month, undo.changes) do
      {:ok, _undone} ->
        {:noreply, changed(socket, nil)}

      _refused ->
        {:noreply,
         socket
         |> changed(nil)
         |> put_flash(:error, "Das wurde inzwischen geändert oder gelöscht.")}
    end
  end

  def handle_event("undo", _params, socket), do: {:noreply, socket}

  def handle_event("edit_target", _params, socket) do
    case socket.assigns.inspector.selected do
      nil ->
        {:noreply, socket}

      entry ->
        {:noreply, assign(socket, :target_form, target_form(entry, socket.assigns.window.focus))}
    end
  end

  def handle_event("cancel_target", _params, socket),
    do: {:noreply, assign(socket, :target_form, nil)}

  def handle_event("target_change", %{"target" => params}, socket) do
    {:noreply, assign(socket, :target_form, TargetForm.to_target_form(params))}
  end

  def handle_event("save_target", %{"target" => params}, socket) do
    with %{category: category} <- socket.assigns.inspector.selected,
         {:ok, attrs} <- TargetForm.attrs(params, socket.assigns.window.focus),
         {:ok, _version} <- Categories.set_target(socket.assigns.current_scope, category, attrs) do
      {:noreply, changed(socket, "Ziel gespeichert.")}
    else
      nil ->
        {:noreply, socket}

      {:error, %Ecto.Changeset{errors: errors}} ->
        {:noreply, target_errors(socket, params, errors)}

      {:error, errors} ->
        {:noreply, target_errors(socket, params, errors)}
    end
  end

  def handle_event("delete_target", _params, socket) do
    with %{category: category} <- socket.assigns.inspector.selected,
         {:ok, _version} <-
           Categories.set_target(socket.assigns.current_scope, category, %{
             from_month: socket.assigns.window.focus,
             cadence: :none
           }) do
      {:noreply, changed(socket, "Ziel gelöscht.")}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("snooze", _params, socket) do
    month = socket.assigns.window.focus

    case socket.assigns.inspector.selected do
      %{category: category, cell: %{target: %{}}} ->
        {:ok, _snooze} = Categories.snooze_target(socket.assigns.current_scope, category, month)
        {:noreply, changed(socket, "Ziel im #{Format.month_name(month)} pausiert.")}

      _other ->
        {:noreply, socket}
    end
  end

  def handle_event("unsnooze", _params, socket) do
    case socket.assigns.inspector.selected do
      %{category: category} ->
        :ok =
          Categories.unsnooze_target(
            socket.assigns.current_scope,
            category,
            socket.assigns.window.focus
          )

        {:noreply, changed(socket, "Ziel läuft wieder.")}

      nil ->
        {:noreply, socket}
    end
  end

  def handle_event("edit_open", params, socket),
    do: {:noreply, assign(socket, :editing, CategoryEditor.open(params, socket.assigns.groups))}

  def handle_event("edit_close", _params, socket),
    do: {:noreply, assign(socket, :editing, closed(socket.assigns.editing))}

  def handle_event(
        "edit_save",
        %{"value" => name},
        %{assigns: %{editing: %{kind: :category}}} = socket
      ),
      do: handle_event("edit_save", %{"name" => name}, socket)

  def handle_event(
        "edit_save",
        %{"name" => name},
        %{assigns: %{editing: %{kind: :category, category: category} = editing}} = socket
      )
      when is_binary(name) do
    if String.trim(name) == category.name,
      do: {:noreply, unchanged(socket, editing)},
      else: save_name(socket, editing, name)
  end

  def handle_event(
        "edit_save",
        %{"name" => name},
        %{assigns: %{editing: %{} = editing}} = socket
      ),
      do: save_name(socket, editing, name)

  def handle_event("edit_back", _params, %{assigns: %{editing: %{step: :delete}}} = socket),
    do: {:noreply, assign(socket, :editing, %{socket.assigns.editing | step: :name, error: nil})}

  def handle_event(
        "edit_delete",
        _params,
        %{assigns: %{editing: %{step: :name, kind: kind}}} = socket
      )
      when kind in [:group, :category] do
    case CategoryEditor.delete(
           socket.assigns.current_scope,
           socket.assigns.editing,
           socket.assigns.groups
         ) do
      :ok -> {:noreply, edited(socket)}
      {:ask, editing} -> {:noreply, assign(socket, :editing, editing)}
      result -> {:noreply, refused(socket, result)}
    end
  end

  # Kept on the server, so a re-render before the confirmed submit keeps the choice.
  def handle_event(
        "edit_delete_change",
        %{"into" => into},
        %{assigns: %{editing: %{step: :delete} = editing}} = socket
      ),
      do: {:noreply, assign(socket, :editing, %{editing | into: into})}

  def handle_event(
        "edit_confirm_delete",
        %{"into" => into},
        %{assigns: %{editing: %{step: :delete}}} = socket
      ) do
    case CategoryEditor.confirm_delete(
           socket.assigns.current_scope,
           socket.assigns.editing,
           into,
           socket.assigns.groups
         ) do
      :ok -> {:noreply, edited(socket)}
      result -> {:noreply, refused(socket, result)}
    end
  end

  def handle_event("delete_group", %{"group" => id}, socket) do
    case CategoryEditor.open(%{"edit" => "group", "group" => id}, socket.assigns.groups) do
      nil -> {:noreply, refused(socket, :gone)}
      edit -> {:noreply, delete_group(socket, edit)}
    end
  end

  def handle_event(
        "sort_category",
        %{"id" => id, "section" => group_id, "index" => index},
        socket
      )
      when is_integer(index) and index >= 0 do
    groups = socket.assigns.groups

    with %Categories.Category{} = category <- find_category(groups, id),
         %Categories.CategoryGroup{} = group <- Enum.find(groups, &(&1.id == group_id)) do
      before_id = group.categories |> Enum.map(& &1.id) |> List.delete(id) |> Enum.at(index)

      case Categories.move_category(socket.assigns.current_scope, id, group.id, before_id) do
        {:error, :name_taken} ->
          message = "In „#{group.name}“ gibt es schon eine Kategorie „#{category.name}“."
          {:noreply, put_flash(socket, :error, message)}

        _moved_or_stale ->
          {:noreply, sorted(socket)}
      end
    else
      nil -> {:noreply, socket}
    end
  end

  def handle_event("sort_group", %{"id" => id, "index" => index}, socket)
      when is_integer(index) and index >= 0 do
    ids = Enum.map(socket.assigns.groups, & &1.id)

    if id in ids do
      before_id = ids |> List.delete(id) |> Enum.at(index)
      Categories.move_category_group(socket.assigns.current_scope, id, before_id)
      {:noreply, sorted(socket)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("sort_" <> _level, _params, socket), do: {:noreply, socket}

  # Late clicks after the popover closed.
  def handle_event("edit_" <> _event, _params, socket), do: {:noreply, socket}

  defp select(socket, id) do
    case find_category(socket.assigns.groups, id) do
      nil ->
        socket

      category ->
        socket
        |> assign(
          selected: category.id,
          popover: closed(socket.assigns.popover),
          editing: category_editing(socket.assigns.groups, category.id),
          target_form: nil
        )
        |> assign_view()
    end
  end

  defp target_form(entry, focus),
    do: entry.cell.target |> TargetForm.params(focus) |> TargetForm.to_target_form()

  defp delete_group(socket, edit) do
    case CategoryEditor.delete(socket.assigns.current_scope, edit, socket.assigns.groups) do
      :ok -> edited(socket)
      result -> refused(socket, result)
    end
  end

  defp focus_shown(socket, param) do
    case shown_month(socket, param) do
      {:ok, month} when month != socket.assigns.window.focus ->
        socket |> assign(:focus, month) |> assign_view()

      _same_or_none ->
        socket
    end
  end

  defp shown_month(socket, param) do
    case Window.parse_param(param) do
      {:ok, month} -> if month in socket.assigns.window.months, do: {:ok, month}, else: :error
      :error -> :error
    end
  end

  defp entry(socket, id) when is_binary(id), do: Inspector.find(socket.assigns.inspector, id)

  defp entry(_socket, _id), do: nil

  defp cover_source(inspector, "rta", _entry), do: {:ready_to_assign, inspector.free}

  defp cover_source(inspector, id, entry) when is_binary(id) do
    with true <- id != entry.category.id,
         %{category: category, cell: cell} <- Inspector.find(inspector, id),
         do: {category, cell.available}
  end

  defp cover_source(_inspector, _id, _entry), do: nil

  defp move(socket, from, to, amount, message) do
    month = socket.assigns.window.focus
    scope = socket.assigns.current_scope

    undoable(socket, month, message, fn ->
      Categories.move_assigned(scope, from, to, month, amount)
    end)
  end

  defp name(:ready_to_assign), do: "„Zu verteilen“"
  defp name(category), do: category.name |> Names.split_emoji() |> elem(1)

  defp auto(socket, "underfunded", month) do
    %{current_scope: scope, current: current} = socket.assigns
    message = &"Ziele mit #{Money.euros(&1)} gefüllt."

    {:noreply, socket} =
      undoable(socket, month, message, fn ->
        Categories.fill_underfunded(scope, month, current)
      end)

    socket
  end

  defp auto(socket, "reset", month) do
    :ok = Categories.reset_assignments(socket.assigns.current_scope, month)
    changed(socket, "Zuweisungen im #{Format.month_name(month)} zurückgesetzt.")
  end

  defp undoable(socket, month, message, write) do
    case Categories.assigned_changes(socket.assigns.current_scope, month, write) do
      {:ok, changes} ->
        moved = changes |> Map.values() |> Enum.map(fn {from, to} -> max(to - from, 0) end)

        {:noreply,
         socket |> changed(nil) |> offer_undo(month, changes, message.(Enum.sum(moved)))}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Der Betrag ist zu groß.")}
    end
  end

  defp offer_undo(socket, _month, changes, _message) when changes == %{}, do: socket

  defp offer_undo(socket, month, changes, message) do
    id = Integer.to_string(System.unique_integer([:positive]))

    socket
    |> assign(:undo, %{id: id, month: month, changes: changes})
    |> put_toast(message, action: "Rückgängig", on_action: JS.push("undo", value: %{id: id}))
  end

  defp changed(socket, message) do
    socket =
      socket
      |> assign(
        popover: closed(socket.assigns.popover),
        target_form: nil,
        invalid: nil,
        undo: nil
      )
      |> assign_budget()
      |> assign_view()
      |> clear_flash()

    if message, do: put_flash(socket, :info, message), else: socket
  end

  defp sorted(socket),
    do: socket |> assign(:undo, nil) |> assign_budget() |> assign_view() |> clear_flash()

  defp closed(nil), do: nil
  defp closed(state), do: %{state | open: false}

  defp target_errors(socket, params, errors),
    do: assign(socket, :target_form, TargetForm.to_target_form(params, errors))

  defp edited(socket) do
    socket =
      socket
      |> assign(editing: closed(socket.assigns.editing), undo: nil)
      |> clear_flash(:toast)
      |> assign_budget()

    socket
    |> assign(:editing, category_editing(socket.assigns.groups, socket.assigns.selected, socket))
    |> assign_view()
  end

  defp category_editing(groups, id, socket \\ nil)

  defp category_editing(_groups, nil, socket), do: socket && socket.assigns.editing

  defp category_editing(groups, id, socket) do
    case CategoryEditor.open(%{"edit" => "category", "category" => to_string(id)}, groups) do
      nil -> socket && socket.assigns.editing
      editing -> editing
    end
  end

  defp save_name(socket, editing, name) do
    case CategoryEditor.save(
           socket.assigns.current_scope,
           %{editing | step: :name, error: nil},
           name
         ) do
      :ok -> {:noreply, socket |> edited() |> renamed(editing)}
      result -> {:noreply, refused(socket, result)}
    end
  end

  defp unchanged(socket, %{step: :name} = editing),
    do: assign(socket, :editing, %{editing | error: nil})

  defp unchanged(socket, _editing), do: socket

  defp renamed(socket, %{kind: :category}), do: put_flash(socket, :info, "Name gespeichert.")
  defp renamed(socket, _editing), do: socket

  defp refused(socket, {:error, editing}), do: assign(socket, :editing, %{editing | open: true})

  defp refused(socket, :gone),
    do: socket |> edited() |> put_flash(:error, "Das wurde inzwischen geändert oder gelöscht.")

  defp edit_for(%{kind: kind} = editing, kind), do: editing
  defp edit_for(_editing, _kind), do: nil

  defp edit_for(%{kind: :group, group: %{id: id}} = editing, :group, id), do: editing
  defp edit_for(%{kind: :new_category, group: %{id: id}} = editing, :group, id), do: editing
  defp edit_for(_editing, _kind, _id), do: nil

  defp assign_amount(socket, _category, _month, value) when not is_binary(value), do: socket

  # An amount that is no number keeps what was typed, marked, so it can be corrected.
  defp assign_amount(socket, category, month, value) do
    case cell_amount(value) do
      {:ok, amount} ->
        store_amount(socket, category, month, amount, value)

      {:error, :too_large} ->
        mark_invalid(socket, category, month, value, Components.out_of_range_amount())

      {:error, _message} ->
        mark_invalid(socket, category, month, value, Components.invalid_amount(value))
    end
  end

  defp cell_amount(value),
    do: if(String.trim(value) == "", do: {:ok, 0}, else: Money.parse_expression(value, 2))

  defp store_amount(socket, category, month, amount, value) do
    if Map.get(socket.assigns.budget.assigned, {category.id, month}, 0) == amount do
      socket |> clear_invalid(category, month) |> assign_view()
    else
      case Categories.assign(socket.assigns.current_scope, category, month, amount) do
        {:ok, _assignment} ->
          socket
          |> clear_invalid(category, month)
          |> assign(:undo, nil)
          |> clear_flash(:toast)
          |> assign_budget()
          |> assign_view()

        {:error, _changeset} ->
          mark_invalid(socket, category, month, value, Components.out_of_range_amount())
      end
    end
  end

  # Another cell's blur comes after a refused cell's, while focus returns to it.
  defp clear_invalid(%{assigns: %{invalid: {id, month, _, _}}} = socket, %{id: id}, month),
    do: assign(socket, :invalid, nil)

  defp clear_invalid(socket, _category, _month), do: socket

  defp mark_invalid(socket, category, month, value, error) do
    field =
      if socket.assigns.fit.compact,
        do: "panel-assign",
        else: "assign-#{category.id}-#{Window.param(month)}"

    socket
    |> assign(:invalid, {category.id, month, value, error})
    |> assign_view()
    |> push_event("refocus_amount", %{id: field})
  end

  defp find_category(groups, id) do
    Enum.find_value(groups, fn group ->
      Enum.find(group.categories, &(&1.id == id))
    end)
  end

  # Groups load with the budget, so a category deleted in another tab leaves both.
  defp assign_budget(socket),
    do:
      assign(socket,
        budget: Categories.budget(socket.assigns.current_scope),
        groups: Categories.list_category_groups(socket.assigns.current_scope)
      )

  defp assign_view(socket) do
    %{budget: budget, current: current, requested: requested, fit: fit, focus: focus} =
      socket.assigns

    months = Budget.months(budget, current, Window.through(requested, current, fit.months))

    window =
      Window.new(requested, hd(months).month, current,
        months: fit.months,
        span: fit.span,
        focus: focus
      )

    by_month = Map.new(months, &{&1.month, &1})
    shown = Enum.map(window.months, &by_month[&1])

    inspector =
      Inspector.new(socket.assigns.groups, months, window.focus, current, socket.assigns.selected)

    socket
    |> assign(
      window: window,
      months: shown,
      inspector: inspector,
      budgeting: for(m <- shown, Status.budgeting?(m, current), into: MapSet.new(), do: m.month),
      rows: Rows.new(socket.assigns.groups, shown)
    )
    |> keep_open(socket.assigns[:window])
  end

  defp keep_open(socket, %Window{focus: focus}) when focus == socket.assigns.window.focus do
    %{popover: popover, inspector: inspector} = socket.assigns

    if popover && !Inspector.find(inspector, popover.category_id),
      do: assign(socket, :popover, nil),
      else: socket
  end

  defp keep_open(socket, _before), do: assign(socket, popover: nil, target_form: nil)

  # A compact budget (below lg) shows one month in a bar, without strip and month heads.
  defp fit(%{"months" => months, "span" => span} = params)
       when is_integer(months) and is_integer(span) do
    compact = params["compact"] == true

    %{
      months: if(compact, do: 1, else: months |> max(1) |> min(3)),
      span: span |> max(5) |> min(12),
      compact: compact
    }
  end

  defp fit(_params), do: @fit
end
