defmodule AbakusWeb.BudgetLive do
  @moduledoc """
  The budget, months side by side as in YNAB 4 and Actual. The first month comes from the URL (`month`, with the
  `filter`). How many months fit and whether the inspector has room, the `BudgetLayout` hook measures in the
  browser (`assets/js/hooks/budget.js`); the browser also gives the current month, so that it is the user's own.
  Every month takes assignments, as in YNAB; Zu verteilen may go below zero.

  A category's name selects it for the inspector (`AbakusWeb.BudgetLive.Inspector`); without room for the
  inspector it opens as a panel over the budget. Targets, snoozing, auto-assign, covering and moving money work
  in the focus month; covering and moving through the available pill's popover (`AbakusWeb.BudgetLive.Popover`).
  """
  use AbakusWeb, :live_view

  alias Abakus.{Budget, Categories}
  alias AbakusWeb.BudgetLive.{Components, Inspector, Popover, Rows, Status, TargetForm, Window}
  alias AbakusWeb.Format

  import AbakusWeb.Format, only: [amount: 1, euros: 1]

  @fit %{months: 1, inspector: false, span: 7}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_scope={@current_scope}
      current={:budget}
      account_groups={@account_groups}
      account_dialog={@account_dialog}
    >
      <h1 class="visually-hidden">Budget</h1>
      <div
        id="budget"
        class="d-flex gap-3 align-items-start"
        phx-hook="BudgetLayout"
        data-fit={"#{@fit.months},#{@fit.inspector},#{@fit.span}"}
      >
        <div class="flex-grow-1 app-min-w-0">
          <Components.filter_chips filter={@filter} counts={@rows.counts} />
          <div class="d-none d-lg-flex mb-2">
            <div class="app-strip-gap"></div>
            <Components.month_strip window={@window} />
          </div>
          <div class="app-budget-wrap">
            <table id="budget-table" class="app-budget">
              <colgroup>
                <col class="app-col-cat" />
                <%= for _month <- @months do %>
                  <col class="app-col-assigned" /><col class="app-col-activity" /><col class="app-col-available" />
                <% end %>
              </colgroup>
              <thead>
                <tr>
                  <th class="app-cat"></th>
                  <th :for={month <- @months} colspan="3" class="app-ms">
                    <Components.month_card
                      month={month}
                      focus={month.month == @window.focus}
                      current={@current}
                    />
                  </th>
                </tr>
                <tr>
                  <th class="app-cat" scope="col"><span class="app-colh">Kategorie</span></th>
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
                />
              </tbody>
              <Components.group
                :for={%{group: group, categories: categories, totals: totals} <- @rows.groups}
                id={"group-#{group.id}"}
                name={group.name}
                months={@window.months}
                totals={totals}
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
                  selected={category.id == @selected}
                />
              </Components.group>
              <Components.income :if={@rows.income != []} rows={@rows.income} months={@months} />
              <tbody :if={@rows.groups == [] and is_nil(@rows.uncategorised)}>
                <tr>
                  <td class="app-cat"></td>
                  <td colspan={3 * length(@months)} class="text-center text-body-secondary py-4">
                    {empty_text(@filter, @window.focus)}
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>
        <aside :if={@fit.inspector} id="inspector" class="app-inspector" aria-label="Details">
          <Inspector.body inspector={@inspector} current={@current} target_form={@target_form} />
        </aside>
      </div>
      <div :if={@inspector.selected && not @fit.inspector} id="panel">
        <div class="offcanvas-backdrop show" phx-click="deselect"></div>
        <div
          class="offcanvas offcanvas-end show app-panel"
          role="dialog"
          aria-modal="true"
          aria-label="Details"
          phx-window-keydown={!@popover && "deselect"}
          phx-key="Escape"
        >
          <div class="offcanvas-header pb-0">
            <button
              type="button"
              class="btn-close ms-auto"
              aria-label="Schließen"
              phx-click="deselect"
            ></button>
          </div>
          <div class="offcanvas-body">
            <Inspector.body
              inspector={@inspector}
              current={@current}
              target_form={@target_form}
              back={false}
            />
          </div>
        </div>
      </div>
      <Popover.popover :if={@popover} popover={@popover} inspector={@inspector} />
    </Layouts.app>
    """
  end

  defp empty_text(:all, _focus), do: "Noch keine Kategorien."
  defp empty_text(:snoozed, focus), do: "Keine pausierten Ziele im #{Format.month_name(focus)}."
  defp empty_text(_filter, _focus), do: "Keine Kategorien in diesem Filter."

  @impl true
  def mount(_params, _session, socket) do
    connect = get_connect_params(socket) || %{}

    {:ok,
     socket
     |> assign(
       page_title: "Budget",
       # The budget computes every month up to the browser's.
       current: Date.beginning_of_month(Format.today(connect["today"])),
       fit: fit(connect["fit"]),
       groups: Categories.list_category_groups(),
       income: Categories.income_by_payee(),
       focus: nil,
       invalid: nil,
       selected: nil,
       popover: nil,
       target_form: nil
     )
     |> assign_budget()}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    requested =
      case Window.parse_param(params["month"]) do
        {:ok, month} -> month
        :error -> socket.assigns.current
      end

    {:noreply,
     socket |> assign(requested: requested, filter: filter(params["filter"])) |> assign_view()}
  end

  @impl true
  def handle_event("fit", params, socket) do
    {:noreply, socket |> assign(:fit, fit(params)) |> assign_view()}
  end

  def handle_event("focus", %{"month" => param}, socket) do
    case shown_month(socket, param) do
      {:ok, month} -> {:noreply, socket |> assign(:focus, month) |> assign_view()}
      :error -> {:noreply, socket}
    end
  end

  def handle_event("show_month", %{"month" => param}, socket) do
    case Window.parse_param(param) do
      {:ok, month} ->
        socket = assign(socket, :focus, month)

        if month in socket.assigns.window.months,
          do: {:noreply, assign_view(socket)},
          else: {:noreply, push_patch(socket, to: budget_path(month, socket.assigns.filter))}

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
     |> push_patch(to: budget_path(Date.shift(first, month: by), socket.assigns.filter))}
  end

  def handle_event("filter", %{"filter" => param}, socket) do
    {:noreply, push_patch(socket, to: budget_path(socket.assigns.window.first, filter(param)))}
  end

  def handle_event("assign", %{"category" => id, "month" => param, "value" => value}, socket) do
    with %Categories.Category{} = category <- find_category(socket.assigns.groups, id),
         {:ok, month} <- shown_month(socket, param) do
      {:noreply, assign_amount(socket, category, month, value)}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("select", %{"category" => id}, socket) do
    case find_category(socket.assigns.groups, id) do
      nil ->
        {:noreply, socket}

      category ->
        {:noreply,
         socket
         |> assign(selected: category.id, popover: nil, target_form: nil)
         |> assign_view()}
    end
  end

  def handle_event("deselect", _params, socket) do
    {:noreply, socket |> assign(selected: nil, target_form: nil) |> assign_view()}
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
      when kind in ["pill", "cover"] do
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
    do: {:noreply, assign(socket, :popover, nil)}

  def handle_event("popover_mode", %{"mode" => mode}, socket) when mode in ["cover", "move"] do
    case socket.assigns.popover do
      %{kind: :pill} = popover ->
        {:noreply,
         assign(socket, :popover, %{popover | mode: String.to_existing_atom(mode), error: nil})}

      _other ->
        {:noreply, socket}
    end
  end

  def handle_event("cover", %{"category" => id, "from" => from}, socket) do
    with %{} = entry <- entry(socket, id),
         {source, available} <- cover_source(socket.assigns.inspector, from, entry),
         amount when amount > 0 <- Popover.cover_amount(entry, available) do
      move(
        socket,
        source,
        entry.category,
        amount,
        "#{euros(amount)} aus #{name(source)} gedeckt."
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
        "#{euros(amount)} von #{name(from)} nach #{name(to)} verschoben."
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
             amount: amount(amount)
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
        "#{euros(amount)} an #{entry.category.name} verteilt."
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
          "#{euros(underfunded)} zugewiesen."
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
        form =
          entry.cell.target
          |> TargetForm.params(socket.assigns.window.focus)
          |> TargetForm.to_target_form()

        {:noreply, assign(socket, :target_form, form)}
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
         {:ok, _version} <- Categories.set_target(category, attrs) do
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
           Categories.set_target(category, %{
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
        {:ok, _snooze} = Categories.snooze_target(category, month)
        {:noreply, changed(socket, "Ziel im #{Format.month_name(month)} pausiert.")}

      _other ->
        {:noreply, socket}
    end
  end

  def handle_event("unsnooze", _params, socket) do
    case socket.assigns.inspector.selected do
      %{category: category} ->
        :ok = Categories.unsnooze_target(category, socket.assigns.window.focus)
        {:noreply, changed(socket, "Ziel läuft wieder.")}

      nil ->
        {:noreply, socket}
    end
  end

  defp shown_month(socket, param) do
    case Window.parse_param(param) do
      {:ok, month} -> if month in socket.assigns.window.months, do: {:ok, month}, else: :error
      :error -> :error
    end
  end

  defp entry(socket, id) when is_binary(id) do
    case Integer.parse(id) do
      {id, ""} -> Inspector.find(socket.assigns.inspector, id)
      _ -> nil
    end
  end

  defp entry(_socket, _id), do: nil

  defp cover_source(inspector, "rta", _entry), do: {:ready_to_assign, inspector.free}

  defp cover_source(inspector, id, entry) when is_binary(id) do
    with {id, ""} <- Integer.parse(id),
         true <- id != entry.category.id,
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
    case Format.parse_amount(text) do
      {:ok, amount} when amount > 0 -> {:ok, amount}
      _ -> {:error, "Bitte einen Betrag über null angeben, etwa 12,50."}
    end
  end

  defp positive_amount(_text), do: {:error, "Bitte einen Betrag angeben."}

  defp move(socket, from, to, amount, message) do
    case Categories.move_assigned(from, to, socket.assigns.window.focus, amount) do
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
    {:ok, _fills} = Categories.fill_underfunded(month, socket.assigns.current, category)
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
    :ok = Categories.reset_assignments(month, category)
    changed(socket, "Zuweisungen im #{Format.month_name(month)} zurückgesetzt.")
  end

  # After a change to the budget: everything recomputed, popover and editor closed.
  defp changed(socket, message) do
    socket =
      socket
      |> assign(popover: nil, target_form: nil, invalid: nil)
      |> assign_budget()
      |> assign_view()
      |> clear_flash()

    if message, do: put_flash(socket, :info, message), else: socket
  end

  defp popover_error(socket, message) do
    case socket.assigns.popover do
      nil -> put_flash(socket, :error, message)
      popover -> assign(socket, :popover, %{popover | error: message})
    end
  end

  defp target_errors(socket, params, errors),
    do: assign(socket, :target_form, TargetForm.to_target_form(params, errors))

  # An amount that is no number keeps what was typed, marked, so it can be corrected.
  defp assign_amount(socket, category, month, value) do
    case Format.parse_amount(value) do
      {:ok, amount} -> store_amount(socket, category, month, amount, value)
      :error -> mark_invalid(socket, category, month, value)
    end
  end

  defp store_amount(socket, category, month, amount, value) do
    if Map.get(socket.assigns.budget.assigned, {category.id, month}, 0) == amount do
      socket |> assign(:invalid, nil) |> assign_view()
    else
      case Categories.assign(category, month, amount) do
        {:ok, _assignment} -> socket |> assign(:invalid, nil) |> assign_budget() |> assign_view()
        {:error, _changeset} -> mark_invalid(socket, category, month, value)
      end
    end
  end

  defp mark_invalid(socket, category, month, value),
    do: socket |> assign(:invalid, {category.id, month, value}) |> assign_view()

  defp find_category(groups, id) do
    Enum.find_value(groups, fn group ->
      Enum.find(
        group.categories,
        &(Integer.to_string(&1.id) == id and not (&1.hidden or group.hidden))
      )
    end)
  end

  defp assign_budget(socket), do: assign(socket, :budget, Categories.budget())

  # Months, rows and the window for the requested first month, what fits and the chosen focus.
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
      Inspector.new(socket.assigns.groups, months, window.focus, socket.assigns.selected)

    socket
    |> assign(
      window: window,
      months: shown,
      inspector: inspector,
      rows:
        Rows.new(socket.assigns.groups, shown,
          focus: window.focus,
          filter: socket.assigns.filter,
          income: socket.assigns.income
        )
    )
    |> keep_open(socket.assigns[:window])
  end

  # The popover and the target editor belong to the focus month and their category.
  defp keep_open(socket, %Window{focus: focus}) when focus == socket.assigns.window.focus do
    %{popover: popover, inspector: inspector} = socket.assigns

    if popover && popover[:category_id] && !Inspector.find(inspector, popover.category_id),
      do: assign(socket, :popover, nil),
      else: socket
  end

  defp keep_open(socket, _before), do: assign(socket, popover: nil, target_form: nil)

  defp filter(param), do: Enum.find(Rows.filters(), :all, &(Atom.to_string(&1) == param))

  defp budget_path(first, :all), do: ~p"/?#{[month: Window.param(first)]}"
  defp budget_path(first, filter), do: ~p"/?#{[filter: filter, month: Window.param(first)]}"

  # What fits as the hook measured it; 3 months at most, a strip of 7 to 12 months.
  defp fit(%{"months" => months, "inspector" => inspector, "span" => span})
       when is_integer(months) and is_integer(span) do
    %{
      months: months |> max(1) |> min(3),
      inspector: inspector == true,
      span: span |> max(7) |> min(12)
    }
  end

  defp fit(_params), do: @fit
end
