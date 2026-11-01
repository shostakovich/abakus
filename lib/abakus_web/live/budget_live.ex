defmodule AbakusWeb.BudgetLive do
  @moduledoc """
  The budget, months side by side as in YNAB 4 and Actual. The first month comes from the URL (`month`). How many
  months fit, the `BudgetLayout` hook measures in the browser (`assets/js/hooks/budget.js`); the browser also gives
  the current month, so that it is the user's own. Every month takes assignments, as in YNAB; Zu verteilen may go
  below zero.

  As in Actual there is no inspector: a month's head shows how Zu verteilen adds up and its Verteilen menu
  auto-assigns or resets the month; a category's name or pencil opens its dialog (`Inspector`: name, target,
  deleting), on phones a sheet that also takes the assignment. Targets, snoozing, auto-assign, covering and moving
  money work in the focus month; covering and moving through the available cell's popover (`Popover`), which makes
  its month the focus. Groups are added, renamed and deleted in popovers (`CategoryEditor`): "+ Gruppe" above the
  table (below it on phones), "+" and the name on a group's row.
  """
  use AbakusWeb, :live_view

  alias Abakus.{Budget, Categories, Format, LocalTime, Money}

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
        title={@open && @inspector.selected.category.name}
        show={@open}
        on_cancel={JS.push("deselect")}
        class="app-dialog"
      >
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
        aria-label="Details"
      >
        <Inspector.sheet
          :if={@open}
          inspector={@inspector}
          current={@current}
          target_form={@target_form}
          assign={panel_assign(@invalid, @inspector)}
          edit={@editing}
        />
        <Popover.editor :if={@popover && @open} popover={@popover} inspector={@inspector} />
      </.modal>
      <Popover.editor :if={@popover && not @open} popover={@popover} inspector={@inspector} />
    </Layouts.app>
    """
  end

  defp focus_month(months, window), do: Enum.find(months, &(&1.month == window.focus))

  defp panel_assign(
         {id, month, typed},
         %Inspector{selected: %{category: %{id: id}, cell: %{month: month}}}
       ),
       do: %{value: typed, invalid: true}

  defp panel_assign(_invalid, %Inspector{selected: %{cell: cell}}),
    do: %{value: Money.amount(cell.assigned), invalid: false}

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
       editing: nil
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

  def handle_event("select", %{"category" => id}, socket),
    do: {:noreply, select(socket, id)}

  def handle_event("deselect", _params, socket) do
    {:noreply, socket |> assign(selected: nil, target_form: nil, editing: nil) |> assign_view()}
  end

  def handle_event("open_popover", %{"kind" => "pick", "month" => param} = params, socket) do
    case shown_month(socket, param) do
      {:ok, month} ->
        socket = socket |> assign(:focus, month) |> assign_view()
        popover = Popover.open(:pick, params["anchor"], nil, socket.assigns.inspector)
        {:noreply, assign(socket, :popover, popover)}

      :error ->
        {:noreply, socket}
    end
  end

  def handle_event("open_popover", %{"kind" => kind, "category" => id} = params, socket)
      when kind in ["available", "cover"] do
    socket = focus_shown(socket, params["month"])

    case entry(socket, id) do
      nil ->
        {:noreply, socket}

      entry ->
        popover =
          Popover.open(
            String.to_existing_atom(kind),
            params["anchor"],
            entry,
            socket.assigns.inspector
          )

        {:noreply, assign(socket, :popover, popover)}
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

  def handle_event("popover_mode", %{"value" => mode}, socket) when mode in ["cover", "move"] do
    case socket.assigns.popover do
      %{kind: :available} = popover ->
        {:noreply,
         assign(socket, :popover, %{popover | mode: String.to_existing_atom(mode), error: nil})}

      _other ->
        {:noreply, socket}
    end
  end

  def handle_event("cover_change", %{"from" => from}, socket) do
    case socket.assigns.popover do
      %{kind: kind} = popover when kind in [:available, :cover] ->
        {:noreply, assign(socket, :popover, %{popover | from: from, error: nil})}

      _other ->
        {:noreply, socket}
    end
  end

  def handle_event("cover_change", _params, socket), do: {:noreply, socket}

  def handle_event("cover", %{"category" => id, "from" => from}, socket) do
    with %{} = entry <- entry(socket, id),
         {source, available} <- cover_source(socket.assigns.inspector, from, entry),
         amount when amount > 0 <- Popover.cover_amount(entry, available) do
      move(
        socket,
        source,
        entry.category,
        amount,
        "#{Money.euros(amount)} aus #{name(source)} gedeckt."
      )
    else
      _ -> {:noreply, popover_error(socket, "Daraus lässt sich nichts decken.")}
    end
  end

  def handle_event("move", %{"category" => id, "other" => other} = params, socket) do
    with %{} = entry <- entry(socket, id),
         {:ok, other} <- other_side(socket, other, entry),
         {:ok, amount} <- positive_amount(params["amount"]) do
      {from, to} =
        if params["direction"] == "from",
          do: {other, entry.category},
          else: {entry.category, other}

      move(
        socket,
        from,
        to,
        amount,
        "#{Money.euros(amount)} von #{name(from)} nach #{name(to)} verschoben."
      )
    else
      {:error, message} -> {:noreply, popover_error(socket, message)}
      _ -> {:noreply, socket}
    end
  end

  def handle_event("pick_change", %{"_target" => ["category"], "category" => id}, socket) do
    case {socket.assigns.popover, entry(socket, id)} do
      {%{kind: :pick} = popover, %{} = entry} ->
        amount = Popover.pick_amount(entry, socket.assigns.inspector.free)

        {:noreply,
         assign(socket, :popover, %{
           popover
           | category_id: entry.category.id,
             amount: Money.amount(amount)
         })}

      _other ->
        {:noreply, socket}
    end
  end

  def handle_event("pick_change", %{"amount" => amount}, socket) when is_binary(amount) do
    case socket.assigns.popover do
      %{kind: :pick} = popover ->
        {:noreply, assign(socket, :popover, %{popover | amount: amount})}

      _other ->
        {:noreply, socket}
    end
  end

  def handle_event("pick_change", _params, socket), do: {:noreply, socket}

  def handle_event("pick", params, socket) do
    with %{} = entry <- entry(socket, params["category"]),
         {:ok, amount} <- positive_amount(params["amount"]) do
      move(
        socket,
        :ready_to_assign,
        entry.category,
        amount,
        "#{Money.euros(amount)} an #{entry.category.name} verteilt."
      )
    else
      {:error, message} -> {:noreply, popover_error(socket, message)}
      _ -> {:noreply, socket}
    end
  end

  def handle_event("auto", %{"kind" => kind, "month" => param} = params, socket)
      when kind in ["underfunded", "reset"] do
    with {:ok, month} <- shown_month(socket, param),
         {:ok, category} <- auto_category(socket, params["category"]) do
      {:noreply, socket |> assign(:focus, month) |> auto(kind, month, category)}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("assign_rest", _params, socket) do
    case socket.assigns.inspector.selected do
      %{cell: %{underfunded: underfunded}} = entry when underfunded > 0 ->
        move(
          socket,
          :ready_to_assign,
          entry.category,
          underfunded,
          "#{Money.euros(underfunded)} zugewiesen."
        )

      _other ->
        {:noreply, socket}
    end
  end

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

  defp other_side(_socket, "rta", _entry), do: {:ok, :ready_to_assign}

  defp other_side(socket, id, entry) do
    case entry(socket, id) do
      %{category: category} when category.id != entry.category.id -> {:ok, category}
      _ -> {:error, "Bitte eine andere Kategorie wählen."}
    end
  end

  defp positive_amount(text) when is_binary(text) do
    case Money.parse(text, 2) do
      {:ok, amount} when amount > 0 -> {:ok, amount}
      {:ok, _not_positive} -> {:error, "Bitte einen Betrag über null angeben, etwa 12,50."}
      {:error, message} -> {:error, message}
    end
  end

  defp positive_amount(_text), do: {:error, "Bitte einen Betrag angeben."}

  defp move(socket, from, to, amount, message) do
    case Categories.move_assigned(
           socket.assigns.current_scope,
           from,
           to,
           socket.assigns.window.focus,
           amount
         ) do
      {:ok, _amount} -> {:noreply, changed(socket, message)}
      {:error, _changeset} -> {:noreply, popover_error(socket, "Der Betrag ist zu groß.")}
    end
  end

  defp name(:ready_to_assign), do: "„Zu verteilen“"
  defp name(category), do: category.name

  defp auto_category(_socket, nil), do: {:ok, nil}

  defp auto_category(socket, id) do
    case entry(socket, id) do
      %{category: category} -> {:ok, category}
      nil -> :error
    end
  end

  defp auto(socket, "underfunded", month, category) do
    {:ok, _fills} =
      Categories.fill_underfunded(
        socket.assigns.current_scope,
        month,
        socket.assigns.current,
        category
      )

    socket = changed(socket, nil)
    inspector = socket.assigns.inspector

    left =
      if category,
        do: Status.open_need(Inspector.find(inspector, category.id).cell),
        else: inspector.month.underfunded

    message =
      if left > 0,
        do: "Nur teilweise gefüllt: Zu verteilen reicht nicht für alle Ziele.",
        else: "Unterfinanzierte Ziele gefüllt."

    put_flash(socket, :info, message)
  end

  defp auto(socket, "reset", month, category) do
    :ok = Categories.reset_assignments(socket.assigns.current_scope, month, category)
    changed(socket, "Zuweisungen im #{Format.month_name(month)} zurückgesetzt.")
  end

  defp changed(socket, message) do
    socket =
      socket
      |> assign(popover: closed(socket.assigns.popover), target_form: nil, invalid: nil)
      |> assign_budget()
      |> assign_view()
      |> clear_flash()

    if message, do: put_flash(socket, :info, message), else: socket
  end

  defp closed(nil), do: nil
  defp closed(state), do: %{state | open: false}

  defp popover_error(socket, message) do
    case socket.assigns.popover do
      nil -> put_flash(socket, :error, message)
      popover -> assign(socket, :popover, %{popover | error: message})
    end
  end

  defp target_errors(socket, params, errors),
    do: assign(socket, :target_form, TargetForm.to_target_form(params, errors))

  defp edited(socket) do
    socket = socket |> assign(:editing, closed(socket.assigns.editing)) |> assign_budget()

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
      {:ok, amount} -> store_amount(socket, category, month, amount, value)
      {:error, _message} -> mark_invalid(socket, category, month, value)
    end
  end

  defp cell_amount(value),
    do: if(String.trim(value) == "", do: {:ok, 0}, else: Money.parse(value, 2))

  defp store_amount(socket, category, month, amount, value) do
    if Map.get(socket.assigns.budget.assigned, {category.id, month}, 0) == amount do
      socket |> assign(:invalid, nil) |> assign_view()
    else
      case Categories.assign(socket.assigns.current_scope, category, month, amount) do
        {:ok, _assignment} -> socket |> assign(:invalid, nil) |> assign_budget() |> assign_view()
        {:error, _changeset} -> mark_invalid(socket, category, month, value)
      end
    end
  end

  defp mark_invalid(socket, category, month, value),
    do: socket |> assign(:invalid, {category.id, month, value}) |> assign_view()

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

    if popover && popover[:category_id] && !Inspector.find(inspector, popover.category_id),
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
