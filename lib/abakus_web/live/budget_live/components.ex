defmodule AbakusWeb.BudgetLive.Components do
  @moduledoc """
  The budget view's parts: month strip, month heads (the month bar on narrow screens) and the table's rows. A month
  before the current one is muted (`app-past`), red stays red; Verfügbar is the tinted anchor column (`app-av`).
  """

  use AbakusWeb, :html

  import Abakus.Format, only: [month_name: 1, month_abbr: 1, month_year: 1]

  alias Abakus.Budget.Month
  alias Abakus.Money
  alias Abakus.Names
  alias AbakusWeb.BudgetLive.{CategoryEditor, Status, Window}

  @doc "The budget's path for the first month shown."
  def budget_path(first), do: ~p"/budget?#{[month: Window.param(first)]}"

  attr :window, Window, required: true

  @doc "The months around the shown ones: the focus month filled, the other shown ones tinted, today underlined."
  def month_strip(assigns) do
    ~H"""
    <div id="strip" class="app-strip" role="group" aria-label="Monate">
      <button
        type="button"
        class="app-step"
        aria-label="Früher"
        disabled={not @window.earlier}
        phx-click="step"
        phx-value-by="-1"
      >
        <.icon name="chevron-left" />
      </button>
      <%= for entry <- @window.strip do %>
        <span :if={entry.year} class="app-year">{entry.year}</span>
        <button
          type="button"
          class={[
            entry.focus && "is-focus",
            entry.visible && not entry.focus && "is-shown",
            entry.current && "is-current"
          ]}
          title={month_year(entry.month)}
          aria-current={entry.current && "date"}
          aria-pressed={to_string(entry.focus)}
          phx-click="show_month"
          phx-value-month={Window.param(entry.month)}
        >
          {month_abbr(entry.month)}
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
        <.icon name="chevron-right" />
      </button>
    </div>
    """
  end

  attr :month, Month, required: true
  attr :focus, :boolean, required: true
  attr :current, Date, required: true

  @doc """
  A month's head, as YNAB 4's month header: the month and its Verteilen menu, YNAB 4's calculation (shown or hidden
  per device) and Zu verteilen, which shows and hides the calculation in every month.
  """
  def month_head(assigns) do
    assigns = assign(assigns, :key, Window.param(assigns.month.month))

    ~H"""
    <div
      id={"month-#{@key}"}
      class={["app-month", @focus && "is-focus"]}
      aria-current={@month.month == @current && "date"}
      phx-click={not @focus && "focus"}
      phx-value-month={@key}
    >
      <div class="app-mhead">
        <span class="app-mname">{title(@month.month, @current)}</span>
        <.distribute month={@month} key={@key} />
      </div>
      <.calculation month={@month} key={@key} />
      <.ready_to_assign month={@month} key={@key} focus={@focus} />
    </div>
    """
  end

  attr :month, Month, required: true
  attr :window, Window, required: true

  @doc """
  The focus month on narrow screens, as a bar that stays at the top: the parts of the month head in the same order,
  with arrows to step through the months.
  """
  def month_bar(assigns) do
    assigns = assign(assigns, :key, Window.param(assigns.month.month))

    ~H"""
    <div id="month-bar" class="app-mbar">
      <div class="app-mhead">
        <span class="app-mname">{month_year(@month.month)}</span>
        <div class="app-mbar-nav">
          <.button
            variant={:ghost}
            size={:sm}
            icon="chevron-left"
            icon_only
            label="Früher"
            disabled={not @window.earlier}
            phx-click="step"
            phx-value-by="-1"
          />
          <.button
            variant={:ghost}
            size={:sm}
            icon="chevron-right"
            icon_only
            label="Später"
            disabled={not @window.later}
            phx-click="step"
            phx-value-by="1"
          />
          <.distribute month={@month} key={@key} />
        </div>
      </div>
      <.calculation month={@month} key={@key} />
      <.ready_to_assign month={@month} key={@key} focus />
    </div>
    """
  end

  attr :month, Month, required: true
  attr :key, :string, required: true

  defp calculation(assigns) do
    ~H"""
    <dl id={"calc-#{@key}"} class="app-mcalc">
      <div :for={{line, index} <- Enum.with_index(Status.calculation(@month))}>
        <dt>{line.label}</dt>
        <dd><.amount value={line.value} signed={index > 0} class={tone_class(line.tone)} /></dd>
      </div>
      <div :for={line <- Status.uncovered(@month)} class="app-mcalc-warn">
        <dt>{line.label}</dt>
        <dd><.amount value={line.value} signed /></dd>
      </div>
    </dl>
    """
  end

  attr :month, Month, required: true
  attr :key, :string, required: true

  defp distribute(assigns) do
    assigns =
      assign(assigns,
        free: Month.free(assigns.month) > 0,
        assigned: assigns.month.assigned != 0
      )

    ~H"""
    <.dropdown
      :if={@free or @assigned}
      id={"distribute-#{@key}"}
      label="Verteilen"
      variant={:ghost}
      chevron={false}
      trigger_class="btn-sm btn-square"
      class="app-distribute"
      align={:end}
    >
      <:trigger><.icon name="ellipsis-vertical" /></:trigger>
      <:item
        :if={@free and @month.underfunded > 0}
        id={"distribute-underfunded-#{@key}"}
        icon="target"
        on_click={JS.push("auto", value: %{kind: "underfunded", month: @key})}
      >
        Unterfinanzierte füllen ({Money.euros(@month.underfunded)})
      </:item>
      <:item
        :if={@free}
        id={"distribute-pick-#{@key}"}
        icon="wallet"
        on_click={
          JS.push("open_popover", value: %{kind: "pick", month: @key, anchor: "distribute-#{@key}"})
        }
      >
        In eine Kategorie …
      </:item>
      <:item
        :if={@assigned}
        id={"distribute-reset-#{@key}"}
        icon="rotate-ccw"
        divider={@free}
        on_click={JS.push("auto", value: %{kind: "reset", month: @key})}
        confirm={"Alle Zuweisungen im #{month_name(@month.month)} zurücksetzen?"}
        confirm_text="Zu verteilen bekommt das Geld zurück."
        confirm_label="Zurücksetzen"
      >
        Zuweisung zurücksetzen
      </:item>
    </.dropdown>
    """
  end

  defp title(%Date{year: year} = month, %Date{year: year}), do: month_name(month)
  defp title(month, _current), do: month_year(month)

  attr :month, Month, required: true
  attr :key, :string, required: true
  attr :focus, :boolean, required: true

  # aria-expanded follows the device's choice, which only the browser knows: the hook sets it.
  defp ready_to_assign(assigns) do
    assigns = assign(assigns, :ready, Status.ready(assigns.month))

    ~H"""
    <button
      id={"calc-toggle-#{@key}"}
      type="button"
      class={["app-rta", elem(@ready, 0) == :success && "is-positive"]}
      aria-expanded="false"
      aria-controls={"calc-#{@key}"}
      phx-hook="CalculationToggle"
      phx-mounted={JS.ignore_attributes("aria-expanded")}
    >
      <span class="app-rta-label">{elem(@ready, 1)}<.icon name="chevron-down" /></span>
      <.amount
        id={"ready-#{@key}"}
        value={@month.ready_to_assign_shown}
        animate={@focus}
        class={["app-rta-value", tone_class(elem(@ready, 0))]}
      />
    </button>
    """
  end

  @doc "The text colour of a tone (`Status`): only the ink tokens colour text."
  def tone_class(:error), do: "text-error-ink"
  def tone_class(:warning), do: "text-warning-ink"
  def tone_class(:success), do: "text-success-ink"
  def tone_class(:muted), do: "text-base-content/70"
  def tone_class(_tone), do: nil

  attr :month, Month, required: true

  @doc "The column heads of a month with its totals."
  def column_heads(assigns) do
    assigns = assign(assigns, :key, Window.param(assigns.month.month))

    ~H"""
    <th
      :for={{field, label} <- [assigned: "Zugewiesen", activity: "Aktivität", available: "Verfügbar"]}
      class={["app-num", @month.closed && "app-past" | field_classes(field)]}
      scope="col"
    >
      <span class="app-colh">{label}</span>
      <span id={"total-#{@key}-#{field}"} class="app-colsum">
        {Money.amount(Map.fetch!(@month, field))}
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

  attr :current, Date, required: true
  attr :group_id, :integer, default: nil, doc: "the group's id when it can be edited"
  attr :edit, :map, default: nil, doc: "the open popover, when it is this group's"
  slot :inner_block

  @doc """
  A group's rows: a collapsible head on a band with its totals per month, blank at zero, then its categories. An
  editable group's name opens its popover (rename, add a category, delete); its "+", shown on hover where there is
  one, adds a category.
  """
  def group(assigns) do
    ~H"""
    <tbody id={"#{@id}-rows"}>
      <tr id={@id} class="app-grp">
        <th class="app-cat" scope="rowgroup">
          <div class="app-grp-head">
            <button
              type="button"
              class="app-fold"
              aria-expanded="true"
              aria-label={"#{@name} auf- und zuklappen"}
              phx-click={
                JS.toggle_class("is-collapsed", to: "##{@id}-rows")
                |> JS.toggle_attribute({"aria-expanded", "true", "false"})
              }
            >
              <.icon name="chevron-down" />
            </button>
            <%= if @group_id do %>
              <button
                id={"edit-group-#{@group_id}"}
                type="button"
                class="app-grp-name"
                aria-expanded={to_string(CategoryEditor.open?(@edit) and @edit.kind == :group)}
                phx-click="edit_open"
                phx-value-edit="group"
                phx-value-group={@group_id}
              >
                {@name}
              </button>
              <.tooltip id={"add-category-#{@group_id}-tip"} text="Kategorie hinzufügen">
                <button
                  id={"add-category-#{@group_id}"}
                  type="button"
                  class="app-add"
                  aria-label={"Kategorie in #{@name} hinzufügen"}
                  aria-expanded={
                    to_string(CategoryEditor.open?(@edit) and @edit.kind == :new_category)
                  }
                  phx-click="edit_open"
                  phx-value-edit="new_category"
                  phx-value-group={@group_id}
                >
                  <.icon name="plus" />
                </button>
              </.tooltip>
            <% else %>
              <span class="app-grp-name">{@name}</span>
            <% end %>
            <CategoryEditor.editor :if={@edit} edit={@edit} />
          </div>
        </th>
        <%= for {month, key, totals} <- group_columns(@months, @totals) do %>
          <td
            :for={field <- [:assigned, :activity, :available]}
            id={Map.has_key?(totals, field) && "#{@id}-#{key}-#{field}"}
            class={[
              "app-num",
              past?(month, @current) && "app-past",
              total_class(field, totals[field]) | field_classes(field)
            ]}
          >
            {totals[field] && blank_zero(totals[field])}
          </td>
        <% end %>
      </tr>
      {render_slot(@inner_block)}
    </tbody>
    """
  end

  defp group_columns(months, totals),
    do: for(month <- months, do: {month, Window.param(month), Map.get(totals, month, %{})})

  defp total_class(:available, total) when is_integer(total) and total < 0, do: "text-error-ink"
  defp total_class(_field, _total), do: nil

  defp field_classes(:assigned), do: ["app-ms"]
  defp field_classes(:activity), do: ["app-quiet"]
  defp field_classes(:available), do: ["app-av"]

  defp past?(month, current), do: Date.before?(month, current)

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
    doc: "false for the uncategorised row, which takes no assignments and links to all accounts"

  attr :compact, :boolean, default: false, doc: "on phones, without the pencil"
  attr :budgeting, :any, required: true, doc: "the months being budgeted (`Status.budgeting?/2`)"

  @doc """
  A category on one line: name, then per month an assign input, activity and available, which opens the popover
  for that month. Zero assigned and activity stay blank. The name, and on desktop a pencil shown on hover and
  focus, open the category's dialog (name, target, delete).
  """
  def category_row(assigns) do
    assigns = assign(assigns, :parts, Names.split_emoji(assigns.name))

    ~H"""
    <tr id={"category-#{@id}"} class="app-row">
      <td class="app-cat">
        <div class="app-catcell">
          <span class="app-emoji" aria-hidden="true">
            <.icon :if={not @assignable} name="triangle-alert" class="app-warn-icon" />{elem(
              @parts,
              0
            )}
          </span>
          <button
            :if={@assignable}
            id={"select-#{@id}"}
            type="button"
            class="app-catbtn"
            title={@name}
            aria-haspopup="dialog"
            phx-click="select"
            phx-value-category={@id}
          >
            {elem(@parts, 1)}
          </button>
          <.link
            :if={not @assignable}
            navigate={~p"/budget/accounts/all"}
            class="app-catbtn"
            title="In allen Konten zuordnen"
          >
            {elem(@parts, 1)}
          </.link>
          <.tooltip
            :if={@assignable and not @compact}
            id={"edit-category-#{@id}-tip"}
            text="Bearbeiten"
            class="app-rowtip"
          >
            <button
              id={"edit-category-#{@id}"}
              type="button"
              class="app-rowact"
              aria-label={"#{@name} bearbeiten"}
              aria-haspopup="dialog"
              phx-click="select"
              phx-value-category={@id}
            >
              <.icon name="pencil" />
            </button>
          </.tooltip>
        </div>
      </td>
      <%= for {month, key, cell, typed} <- columns(@months, @cells, @id, @invalid) do %>
        <td class={["app-ms app-num", past?(month, @current) && "app-past"]}>
          <input
            :if={@assignable}
            id={"assign-#{@id}-#{key}"}
            class="app-assign"
            value={typed || blank_zero(cell.assigned)}
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
        <td
          id={"activity-#{@id}-#{key}"}
          class={["app-num app-quiet", past?(month, @current) && "app-past"]}
        >
          {blank_zero(cell.activity)}
        </td>
        <td
          id={"available-#{@id}-#{key}"}
          class={["app-num app-av", past?(month, @current) && "app-past"]}
        >
          <.available
            cell={cell}
            budgeting={month in @budgeting}
            id={@assignable && "available-button-#{@id}-#{key}"}
          />
        </td>
      <% end %>
    </tr>
    """
  end

  defp columns(months, cells, id, invalid) do
    for month <- months, do: {month, Window.param(month), cells[month], typed(invalid, id, month)}
  end

  defp typed({id, month, typed}, id, month), do: typed
  defp typed(_invalid, _id, _month), do: nil

  defp blank_zero(0), do: nil
  defp blank_zero(amount), do: Money.amount(amount)

  attr :cell, :any, required: true
  attr :budgeting, :boolean, required: true, doc: "whether its month is being budgeted"
  attr :id, :any, default: nil, doc: "set for a cell that opens the popover"

  @doc """
  A cell's available amount, coloured and marked by its status (`Status.available/2`): an underfunded target's ring
  fills by the share of the month's need that is assigned.
  """
  def available(assigns) do
    assigns = assign(assigns, :status, Status.available(assigns.cell, assigns.budgeting))

    ~H"""
    <button
      :if={@id}
      id={@id}
      type="button"
      class={["app-avail", available_class(@status.tone)]}
      aria-label={available_label(@status, @cell)}
      phx-click="open_popover"
      phx-value-kind="available"
      phx-value-category={@cell.category_id}
      phx-value-month={Window.param(@cell.month)}
      phx-value-anchor={@id}
    >
      <.available_content status={@status} cell={@cell} />
    </button>
    <span :if={!@id} class={["app-avail", available_class(@status.tone)]}>
      <.available_content status={@status} cell={@cell} />
      <span :if={@status.label} class="sr-only">{@status.label}</span>
    </span>
    """
  end

  attr :status, :map, required: true
  attr :cell, :any, required: true

  defp available_content(assigns) do
    ~H"""
    {Money.amount(@cell.available)}<span class="app-mark"><.icon
      :if={@status.icon}
      name={@status.icon}
      class={icon_class(@status.icon)}
    /><.ring :if={@status.ring} share={@status.ring} /></span>
    """
  end

  attr :share, :integer, required: true

  defp ring(assigns) do
    ~H"""
    <svg class="app-ring" viewBox="0 0 16 16" aria-hidden="true">
      <circle class="app-ring-track" cx="8" cy="8" r="6" />
      <circle
        class="app-ring-fill"
        cx="8"
        cy="8"
        r="6"
        pathLength="100"
        stroke-dasharray={"#{@share} 100"}
        transform="rotate(-90 8 8)"
      />
    </svg>
    """
  end

  defp available_class(:muted), do: "app-zero"
  defp available_class(tone), do: tone_class(tone)

  defp icon_class("circle-check"), do: "text-success-ink"
  defp icon_class("pause"), do: "text-base-content/70"
  defp icon_class(_icon), do: nil

  defp available_label(status, cell) do
    state = if status.label, do: ", #{status.label}"
    "Verfügbar #{Money.euros(cell.available)}#{state}, Geld verschieben"
  end
end
