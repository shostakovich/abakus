defmodule AbakusWeb.BudgetLive do
  @moduledoc """
  The budget, months side by side as in YNAB 4 and Actual. The first month comes from the URL (`month`, with the
  `filter`). How many months fit and whether the inspector has room, the `BudgetLayout` hook measures in the
  browser (`assets/js/hooks/budget.js`); the browser also gives the current month, so that it is the user's own.
  Every month takes assignments, as in YNAB; Zu verteilen may go below zero.
  """
  use AbakusWeb, :live_view

  alias Abakus.{Budget, Categories}
  alias AbakusWeb.BudgetLive.{Components, Rows, Window}
  alias AbakusWeb.Format

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
        <Components.inspector :if={@fit.inspector} month={focus_month(assigns)} />
      </div>
    </Layouts.app>
    """
  end

  defp empty_text(:all, _focus), do: "Noch keine Kategorien."
  defp empty_text(:snoozed, focus), do: "Keine pausierten Ziele im #{Format.month_name(focus)}."
  defp empty_text(_filter, _focus), do: "Keine Kategorien in diesem Filter."

  defp focus_month(%{months: months, window: window}),
    do: Enum.find(months, &(&1.month == window.focus))

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
       invalid: nil
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
    with {:ok, month} <- Window.parse_param(param),
         true <- month in socket.assigns.window.months do
      {:noreply, socket |> assign(:focus, month) |> assign_view()}
    else
      _ -> {:noreply, socket}
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
         {:ok, month} <- Window.parse_param(param),
         true <- month in socket.assigns.window.months do
      {:noreply, assign_amount(socket, category, month, value)}
    else
      _ -> {:noreply, socket}
    end
  end

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

    assign(socket,
      window: window,
      months: shown,
      rows:
        Rows.new(socket.assigns.groups, shown,
          focus: window.focus,
          filter: socket.assigns.filter,
          income: socket.assigns.income
        )
    )
  end

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
