defmodule AbakusWeb.BudgetLive.Components do
  @moduledoc """
  The budget view's parts: filter chips, month strip, month cards and the table's rows. The focus
  month's card is outlined and its column shows pills, the category's target bar follows it; the other months
  stay quiet.
  """

  use AbakusWeb, :html

  import AbakusWeb.Format

  alias Abakus.Names
  alias AbakusWeb.BudgetLive.{CategoryEditor, Status, Window}

  attr :filter, :atom, required: true
  attr :counts, :map, required: true

  @doc "The filter chips; the `FilterChips` hook folds the trailing ones into \"Filter\" while the row is too short."
  def filter_chips(assigns) do
    assigns = assign(assigns, :chips, chips(assigns.counts))

    ~H"""
    <div id="filters" class="app-chips mb-2" role="group" aria-label="Filter" phx-hook="FilterChips">
      <button
        :for={{key, label, tone} <- @chips}
        type="button"
        class={["btn btn-sm btn-pill", chip_class(key == @filter, tone)]}
        aria-pressed={to_string(key == @filter)}
        data-chip={key}
        phx-click="filter"
        phx-value-filter={key}
      >
        <.icon :if={tone} name="alert" class="app-icon-sm" />{label}
      </button>
      <div
        id="filters-more"
        class="dropdown"
        hidden
        phx-click-away={hide_dropdown("#filters-menu", "#filters-toggle")}
      >
        <button
          id="filters-toggle"
          type="button"
          class="btn btn-sm btn-pill btn-light dropdown-toggle"
          aria-expanded="false"
          aria-controls="filters-menu"
          phx-click={toggle_dropdown("#filters-menu", "#filters-toggle")}
        >
          Filter
        </button>
        <ul id="filters-menu" class="dropdown-menu dropdown-menu-end" data-bs-popper="static">
          <li :for={{key, label, _tone} <- @chips} data-fold={key} hidden>
            <button
              type="button"
              class={["dropdown-item", key == @filter && "active"]}
              phx-click={
                JS.push("filter", value: %{filter: key})
                |> hide_dropdown("#filters-menu", "#filters-toggle")
              }
            >
              {label}
            </button>
          </li>
        </ul>
      </div>
    </div>
    """
  end

  defp chips(counts) do
    [
      {:all, "Alle", nil},
      {:overspent, "#{counts.overspent} überzogen", if(counts.overspent > 0, do: :danger)},
      {:underfunded, counted("Unterfinanziert", counts.underfunded), nil},
      {:overfunded, "Überfinanziert", nil},
      {:available, "Geld verfügbar", nil},
      {:snoozed, counted("Pausiert", counts.snoozed), nil}
    ]
  end

  defp counted(label, 0), do: label
  defp counted(label, count), do: "#{label} · #{count}"

  defp chip_class(true = _active, _tone), do: "btn-primary"
  defp chip_class(false, :danger), do: "btn-outline-danger"
  defp chip_class(false, nil), do: "btn-light"

  attr :window, Window, required: true

  @doc "The months around the shown ones: the focus month filled, the other shown ones tinted, today underlined."
  def month_strip(assigns) do
    ~H"""
    <div id="strip" class="card app-strip" role="group" aria-label="Monate">
      <button
        type="button"
        class="app-step"
        aria-label="Früher"
        disabled={not @window.earlier}
        phx-click="step"
        phx-value-by="-1"
      >
        <.icon name="back" />
      </button>
      <%= for entry <- @window.strip do %>
        <span :if={entry.year} class="app-year">{entry.year}</span>
        <button
          type="button"
          class={[
            entry.focus && "is-focus",
            entry.visible && not entry.focus && "is-sel",
            entry.current && "is-cur"
          ]}
          title={month_year(entry.month)}
          aria-current={entry.current && "date"}
          phx-click="show_month"
          phx-value-month={Window.param(entry.month)}
        >
          {month_short(entry.month)}
        </button>
      <% end %>
      <button
        type="button"
        class="app-step"
        aria-label="Später"
        disabled={not @window.later}
        phx-click="step"
        phx-value-by="1"
      >
        <.icon name="chevron" />
      </button>
    </div>
    """
  end

  attr :month, Abakus.Budget.Month, required: true
  attr :focus, :boolean, required: true
  attr :current, Date, required: true

  @doc """
  A month's card, as clean as YNAB's: Zu verteilen, with a sign while later months are not covered. The current
  month stands out by its background, as in Actual, the focus month by its outline; how Zu verteilen adds up and
  which months are short is in the inspector.
  """
  def month_card(assigns) do
    assigns = assign(assigns, :key, Window.param(assigns.month.month))

    ~H"""
    <div
      id={"month-#{@key}"}
      class={["card app-mcard", @focus && "is-focus", @month.month == @current && "is-current"]}
      aria-current={@month.month == @current && "date"}
      phx-click={not @focus && "focus"}
      phx-value-month={@key}
    >
      <div class="card-body p-2 d-flex flex-column align-items-center gap-1 text-center">
        <span class="app-mname">{title(@month.month, @current)}</span>
        <.ready_to_assign month={@month} key={@key} />
        <.distribute :if={@month.ready_to_assign_shown > 0} key={@key} />
      </div>
    </div>
    """
  end

  attr :key, :string, required: true

  # "Verteilen ▾" while money is unassigned, as in YNAB: fill the underfunded or pick a category.
  defp distribute(assigns) do
    ~H"""
    <div
      class="dropdown"
      phx-click-away={hide_dropdown("#distribute-#{@key}", "#distribute-toggle-#{@key}")}
    >
      <button
        id={"distribute-toggle-#{@key}"}
        type="button"
        class="btn btn-sm btn-success dropdown-toggle"
        aria-expanded="false"
        aria-controls={"distribute-#{@key}"}
        phx-click={toggle_dropdown("#distribute-#{@key}", "#distribute-toggle-#{@key}")}
      >
        Verteilen
      </button>
      <ul id={"distribute-#{@key}"} class="dropdown-menu" data-bs-popper="static">
        <li>
          <button
            id={"distribute-underfunded-#{@key}"}
            type="button"
            class="dropdown-item"
            phx-click={
              JS.push("auto", value: %{kind: "underfunded", month: @key})
              |> hide_dropdown("#distribute-#{@key}", "#distribute-toggle-#{@key}")
            }
          >
            Unterfinanzierte füllen
          </button>
        </li>
        <li><hr class="dropdown-divider" /></li>
        <li>
          <button
            id={"distribute-pick-#{@key}"}
            type="button"
            class="dropdown-item"
            phx-click={
              JS.push("open_popover",
                value: %{kind: "pick", month: @key, anchor: "distribute-toggle-#{@key}"}
              )
              |> hide_dropdown("#distribute-#{@key}", "#distribute-toggle-#{@key}")
            }
          >
            In eine Kategorie …
          </button>
        </li>
      </ul>
    </div>
    """
  end

  # The year only when it is not this year's.
  defp title(%Date{year: year} = month, %Date{year: year}), do: month_name(month)
  defp title(month, _current), do: month_year(month)

  attr :month, Abakus.Budget.Month, required: true
  attr :key, :string, required: true

  defp ready_to_assign(assigns) do
    assigns = assign(assigns, :status, Status.ready(assigns.month))

    ~H"""
    <div class="app-min-w-0 mt-auto">
      <div id={"ready-#{@key}"} class={["app-rta-big", elem(@status, 0)]}>
        {euros(@month.ready_to_assign_shown)}
      </div>
      <div class="fw-semibold d-flex align-items-center justify-content-center gap-1">
        {elem(@status, 1)}
        <span
          :if={@month.uncovered != []}
          class="app-uncovered text-danger d-inline-flex"
          title={Enum.join(Status.uncovered(@month), "\n")}
        >
          <.icon name="alert" class="app-icon-sm" />
          <span class="visually-hidden">{Enum.join(Status.uncovered(@month), ", ")}</span>
        </span>
      </div>
    </div>
    """
  end

  attr :month, Abakus.Budget.Month, required: true

  @doc "The column heads of a month with its totals."
  def column_heads(assigns) do
    assigns = assign(assigns, :key, Window.param(assigns.month.month))

    ~H"""
    <th
      :for={{field, label} <- [assigned: "Zugewiesen", activity: "Aktivität", available: "Verfügbar"]}
      class={["app-num", field == :assigned && "app-ms"]}
      scope="col"
    >
      <span class="app-colh">
        {label}<b id={"total-#{@key}-#{field}"}>{amount(Map.fetch!(@month, field))}</b>
      </span>
    </th>
    """
  end

  attr :id, :string, required: true
  attr :name, :string, required: true
  attr :months, :list, required: true

  attr :totals, :map,
    required: true,
    doc: "per month the totals shown: assigned, activity, available"

  attr :group_id, :integer, default: nil, doc: "the group's id when it can be edited"
  attr :edit, :map, default: nil, doc: "the open popover, when it is this group's"
  slot :inner_block

  @doc """
  A group's rows: a collapsible head with its totals per month, then its categories. An editable group's name
  opens its popover, its "+" (shown on hover) adds a category.
  """
  def group(assigns) do
    ~H"""
    <tbody id={"#{@id}-rows"}>
      <tr id={@id} class="app-grp">
        <th class={["app-cat", @edit && "has-pop"]} scope="rowgroup">
          <div class="dropdown app-grp-head">
            <button
              type="button"
              class="app-catbtn app-fold"
              aria-expanded="true"
              aria-label={"#{@name} auf- und zuklappen"}
              phx-click={
                JS.toggle_class("is-collapsed", to: "##{@id}-rows")
                |> JS.toggle_attribute({"aria-expanded", "true", "false"})
              }
            >
              <.icon name="down" class="app-icon-sm" />
            </button>
            <%= if @group_id do %>
              <button
                id={"edit-group-#{@group_id}"}
                type="button"
                class="app-catbtn app-label"
                aria-expanded={to_string(@edit != nil and @edit.kind == :group)}
                phx-click="edit_open"
                phx-value-edit="group"
                phx-value-group={@group_id}
              >
                {@name}
              </button>
              <button
                id={"add-category-#{@group_id}"}
                type="button"
                class="app-add"
                title="Kategorie hinzufügen"
                aria-label={"Kategorie in #{@name} hinzufügen"}
                aria-expanded={to_string(@edit != nil and @edit.kind == :new_category)}
                phx-click="edit_open"
                phx-value-edit="new_category"
                phx-value-group={@group_id}
              >
                <.icon name="plus" class="app-icon-sm" />
              </button>
            <% else %>
              <span class="app-label">{@name}</span>
            <% end %>
            <CategoryEditor.popover :if={@edit} edit={@edit} />
          </div>
        </th>
        <%= for {key, totals} <- Enum.map(@months, &{Window.param(&1), Map.get(@totals, &1, %{})}) do %>
          <td
            :for={field <- [:assigned, :activity, :available]}
            id={Map.has_key?(totals, field) && "#{@id}-#{key}-#{field}"}
            class={["app-num", field == :assigned && "app-ms", total_class(field, totals[field])]}
          >
            {totals[field] && amount(totals[field])}
          </td>
        <% end %>
      </tr>
      {render_slot(@inner_block)}
    </tbody>
    """
  end

  defp total_class(_field, nil), do: nil
  defp total_class(_field, 0), do: "app-zero"
  defp total_class(:available, total) when total < 0, do: "app-neg"
  defp total_class(_field, _total), do: nil

  attr :id, :any, required: true, doc: "the category's id, or \"uncategorised\""
  attr :name, :string, required: true
  attr :cells, :map, required: true, doc: "the category's `Abakus.Budget.CategoryMonth` per month"
  attr :months, :list, required: true
  attr :focus, Date, required: true
  attr :current, Date, required: true

  attr :invalid, :any,
    required: true,
    doc: "`{category_id, month, typed}` for the amount that was no number"

  attr :assignable, :boolean,
    default: true,
    doc: "false for the uncategorised row, which takes no assignments and cannot be selected"

  attr :selected, :boolean, default: false

  @doc """
  A category: name with target bar (its status on hover), then per month an assign input, activity and available (a
  pill in the focus month, which opens the popover). Its name selects it for the inspector.
  """
  def category_row(assigns) do
    ~H"""
    <tr id={"category-#{@id}"} class={@selected && "is-sel"}>
      <td class="app-cat">
        <button
          :if={@assignable}
          id={"select-#{@id}"}
          type="button"
          class="app-catbtn"
          aria-pressed={to_string(@selected)}
          phx-click={if @selected, do: "deselect", else: "select"}
          phx-value-category={@id}
        >
          <.category_name name={@name} />
        </button>
        <.category_name :if={not @assignable} name={@name} icon="alert" />
        <.target_line line={Status.target_line(@cells[@focus])} />
      </td>
      <%= for {month, key, cell, typed} <- columns(@months, @cells, @id, @invalid) do %>
        <td class="app-ms app-num">
          <input
            :if={@assignable}
            id={"assign-#{@id}-#{key}"}
            class={[
              "form-control form-control-sm app-assign",
              cell.assigned == 0 && "app-zero",
              typed && "is-invalid"
            ]}
            value={typed || amount(cell.assigned)}
            inputmode="decimal"
            autocomplete="off"
            aria-label={"#{@name}, zugewiesen im #{month_year(month)}"}
            aria-invalid={typed && "true"}
            title={typed && "Kein gültiger Betrag"}
            phx-blur="assign"
            phx-focus={month != @focus && "focus"}
            phx-value-category={@id}
            phx-value-month={key}
          />
        </td>
        <td id={"activity-#{@id}-#{key}"} class={["app-num", activity_class(cell.activity)]}>
          {amount(cell.activity)}
        </td>
        <td id={"available-#{@id}-#{key}"} class="app-num">
          <.pill :if={month == @focus} cell={cell} id={@assignable && "pill-#{@id}-#{key}"} />
          <.quiet :if={month != @focus} cell={cell} current={@current} />
        </td>
      <% end %>
    </tr>
    """
  end

  # Per month: the key, the cell and what was typed if it was no number.
  defp columns(months, cells, id, invalid) do
    for month <- months, do: {month, Window.param(month), cells[month], typed(invalid, id, month)}
  end

  defp typed({id, month, typed}, id, month), do: typed
  defp typed(_invalid, _id, _month), do: nil

  defp activity_class(0), do: "app-zero"
  defp activity_class(_activity), do: "text-body-secondary"

  attr :name, :string, required: true
  attr :icon, :any, default: nil

  defp category_name(assigns) do
    assigns = assign(assigns, :parts, Names.split_emoji(assigns.name))

    ~H"""
    <span class="app-catname">
      <span class="app-emoji" aria-hidden="true">
        <.icon :if={@icon} name={@icon} class="app-icon-sm text-warning" />{elem(@parts, 0)}
      </span>
      <span class="app-label" title={@name}>{elem(@parts, 1)}</span>
    </span>
    """
  end

  attr :line, :any, required: true

  defp target_line(%{line: nil} = assigns), do: ~H""

  defp target_line(assigns) do
    ~H"""
    <span class="app-line2"><.target_bar line={@line} /></span>
    """
  end

  attr :line, :map, required: true, doc: "from `Status.target_line/1`"

  @doc "A target's bar, its status as the title."
  def target_bar(assigns) do
    ~H"""
    <span class="progress app-target" title={@line.title}>
      <span
        :for={{percent, class} <- @line.bars}
        class={["progress-bar", class, "app-w-#{percent}"]}
      ></span>
    </span>
    """
  end

  attr :cell, :any, required: true
  attr :id, :any, default: nil, doc: "set for a pill that opens the popover"

  @doc "A cell's available amount as a pill coloured by its status."
  def pill(assigns) do
    assigns = assign(assigns, :status, Status.pill(assigns.cell))

    ~H"""
    <button
      :if={@id}
      id={@id}
      type="button"
      class={["app-pill", pill_class(@status)]}
      aria-label={"Verfügbar #{euros(@cell.available)}, Geld verschieben"}
      phx-click="open_popover"
      phx-value-kind="pill"
      phx-value-category={@cell.category_id}
      phx-value-anchor={@id}
    >
      <.icon :if={pill_icon(@status)} name={pill_icon(@status)} />{pill_text(@status, @cell)}
    </button>
    <span :if={!@id} class={["app-pill", pill_class(@status)]}>
      <.icon :if={pill_icon(@status)} name={pill_icon(@status)} />{pill_text(@status, @cell)}
    </span>
    """
  end

  defp pill_class(:zero), do: "app-pill-zero"
  defp pill_class({class, _icon}), do: ["badge rounded-pill", class]
  defp pill_icon(:zero), do: nil
  defp pill_icon({_class, icon}), do: icon
  defp pill_text(:zero, _cell), do: amount(0)
  defp pill_text(_status, cell), do: euros(cell.available)

  attr :cell, :any, required: true
  attr :current, Date, required: true

  defp quiet(assigns) do
    assigns = assign(assigns, :status, Status.quiet(assigns.cell, assigns.current))

    ~H"""
    <span class={["app-q", @status.class]}>
      <span :if={@status.dot} class="app-udot" title="unterfinanziert"></span>{amount(@cell.available)}
    </span>
    """
  end

  attr :rows, :list, required: true, doc: "income per payee: `%{payee, amounts}`"
  attr :months, :list, required: true, doc: "the shown `Abakus.Budget.Month`s"

  @doc "The income group: income per payee in the activity column."
  def income(assigns) do
    assigns =
      assigns
      |> assign(:totals, Map.new(assigns.months, &{&1.month, %{activity: &1.income}}))
      |> assign(:months, Enum.map(assigns.months, & &1.month))

    ~H"""
    <.group id="group-income" name="💰 Einnahmen" months={@months} totals={@totals}>
      <tr :for={row <- @rows} class="app-inc">
        <td class="app-cat">
          <.category_name name={row.payee || "Ohne Empfänger"} />
        </td>
        <%= for value <- Enum.map(@months, &Map.get(row.amounts, &1, 0)) do %>
          <td class="app-ms"></td>
          <td class={["app-num", value == 0 && "app-zero"]}>{amount(value)}</td>
          <td></td>
        <% end %>
      </tr>
    </.group>
    """
  end
end
