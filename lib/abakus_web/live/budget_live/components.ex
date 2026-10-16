defmodule AbakusWeb.BudgetLive.Components do
  @moduledoc """
  The budget view's parts: month strip, month cards (the month bar on narrow screens) and the table's rows. The
  focus month shows pills; the other months stay quiet.
  """

  use AbakusWeb, :html

  import AbakusWeb.Format

  alias Abakus.Budget.Month
  alias Abakus.Money
  alias Abakus.Names
  alias AbakusWeb.BudgetLive.{CategoryEditor, MonthDetails, Status, Window}

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
        <.icon name="chevron-right" />
      </button>
    </div>
    """
  end

  attr :month, Month, required: true
  attr :future, :list, required: true, doc: "from `MonthDetails.future/2`"
  attr :focus, :boolean, required: true
  attr :current, Date, required: true

  @doc """
  A month's card, as compact as Actual's: Zu verteilen on a fill that carries its state, a sign while later months
  are not covered, and Verteilen. The rest opens in the month's popover.
  """
  def month_card(assigns) do
    assigns =
      assign(assigns,
        key: Window.param(assigns.month.month),
        tone: elem(Status.ready(assigns.month), 0)
      )

    ~H"""
    <div
      id={"month-#{@key}"}
      class={["app-mcard", card_class(@tone), @focus && "is-focus"]}
      aria-current={@month.month == @current && "date"}
      phx-click={not @focus && "focus"}
      phx-value-month={@key}
    >
      <.month_info key={@key} focus={@focus}>
        <span class="app-mname">{title(@month.month, @current)}</span>
        <.ready_to_assign month={@month} key={@key} focus={@focus} />
      </.month_info>
      <.distribute month={@month} key={@key} primary={@focus} />
    </div>
    <MonthDetails.details
      id={"month-details-#{@key}"}
      anchor={"month-info-#{@key}"}
      month={@month}
      future={@future}
    />
    """
  end

  attr :month, Month, required: true
  attr :future, :list, required: true
  attr :window, Window, required: true

  @doc """
  The focus month on narrow screens, as a bar that stays at the top: the month with arrows to step, and
  Zu verteilen with its menu on a band like the month card.
  """
  def month_bar(assigns) do
    assigns =
      assign(assigns,
        key: Window.param(assigns.month.month),
        tone: elem(Status.ready(assigns.month), 0)
      )

    ~H"""
    <div id="month-bar" class="app-mbar">
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
        <span class="app-mname">{month_year(@month.month)}</span>
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
      </div>
      <div id={"month-#{@key}"} class={["app-mcard app-mbar-card", card_class(@tone)]}>
        <.month_info key={@key} focus>
          <.ready_to_assign month={@month} key={@key} focus />
        </.month_info>
        <.distribute month={@month} key={@key} primary />
      </div>
      <MonthDetails.details
        id={"month-details-#{@key}"}
        anchor={"month-info-#{@key}"}
        month={@month}
        future={@future}
      />
    </div>
    """
  end

  attr :key, :string, required: true
  attr :focus, :boolean, required: true
  slot :inner_block, required: true

  defp month_info(assigns) do
    assigns = assign(assigns, :open, show_popover("month-details-#{assigns.key}"))

    ~H"""
    <button
      id={"month-info-#{@key}"}
      type="button"
      class="app-minfo"
      aria-haspopup="dialog"
      phx-click={
        if @focus, do: @open, else: JS.push("focus", value: %{month: @key}) |> JS.concat(@open)
      }
    >
      {render_slot(@inner_block)}
    </button>
    """
  end

  attr :month, Month, required: true
  attr :key, :string, required: true
  attr :primary, :boolean, default: false

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
      trigger_class={["btn-sm", @primary && @free && "btn-primary"]}
      class="app-distribute"
      align={:end}
    >
      <:trigger>Verteilen</:trigger>
      <:item
        :if={@free and @month.underfunded > 0}
        id={"distribute-underfunded-#{@key}"}
        icon="target"
        on_click={JS.push("auto", value: %{kind: "underfunded", month: @key})}
      >
        Unterfinanzierte füllen
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

  defp card_class(:success), do: "app-mcard-success"
  defp card_class(:error), do: "app-mcard-error"
  defp card_class(_tone), do: nil

  defp title(%Date{year: year} = month, %Date{year: year}), do: month_name(month)
  defp title(month, _current), do: month_year(month)

  attr :month, Month, required: true
  attr :key, :string, required: true
  attr :focus, :boolean, required: true

  defp ready_to_assign(assigns) do
    ~H"""
    <.amount
      id={"ready-#{@key}"}
      value={@month.ready_to_assign_shown}
      animate={@focus}
      class="app-rta-value"
    />
    <span class="app-rta-label">
      {elem(Status.ready(@month), 1)}
      <span :if={@month.uncovered != []} id={"uncovered-#{@key}"} class="app-uncovered">
        <.icon name="triangle-alert" />nicht gedeckt
      </span>
    </span>
    """
  end

  @doc "The text colour of a tone (`Status`): only the ink tokens colour text."
  def tone_class(:error), do: "text-error-ink"
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
      class={["app-num", field == :assigned && "app-ms"]}
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

  attr :group_id, :integer, default: nil, doc: "the group's id when it can be edited"
  attr :edit, :map, default: nil, doc: "the open popover, when it is this group's"
  slot :inner_block

  @doc """
  A group's rows: a collapsible head with its totals per month, then its categories. An editable group's name
  opens its popover (rename, add a category, delete); its "+", shown on hover where there is one, adds a category.
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
        <%= for {key, totals} <- group_columns(@months, @totals) do %>
          <td
            :for={field <- [:assigned, :activity, :available]}
            id={Map.has_key?(totals, field) && "#{@id}-#{key}-#{field}"}
            class={[
              "app-num",
              field == :assigned && "app-ms",
              total_class(field, totals[field])
            ]}
          >
            {totals[field] && Money.amount(totals[field])}
            <span :if={field == :available and only_activity?(totals)} class="app-alt">
              {Money.amount(totals.activity)}
            </span>
          </td>
        <% end %>
      </tr>
      {render_slot(@inner_block)}
    </tbody>
    """
  end

  defp group_columns(months, totals),
    do: for(month <- months, do: {Window.param(month), Map.get(totals, month, %{})})

  # Income has activity alone; phones, which hide that column, show it under Verfügbar.
  defp only_activity?(totals),
    do: Map.has_key?(totals, :activity) and not Map.has_key?(totals, :available)

  defp total_class(_field, nil), do: nil
  defp total_class(_field, 0), do: "app-zero"
  defp total_class(:available, total) when total < 0, do: "text-error-ink"
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
    doc: "false for the uncategorised row, which takes no assignments and links to all accounts"

  attr :compact, :boolean, default: false, doc: "on phones, without the pencil"

  @doc """
  A category on one line: name, then per month an assign input, activity and available (a pill in the focus
  month, which opens the popover). The name, and on desktop a pencil shown on hover and focus, open the
  category's dialog (name, target, delete).
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
        <td class="app-ms app-num">
          <input
            :if={@assignable}
            id={"assign-#{@id}-#{key}"}
            class={["app-assign", cell.assigned == 0 && "app-zero"]}
            value={typed || Money.amount(cell.assigned)}
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
          class={[
            "app-num",
            if(cell.activity == 0, do: "app-zero", else: "app-quiet")
          ]}
        >
          {Money.amount(cell.activity)}
        </td>
        <td id={"available-#{@id}-#{key}"} class="app-num">
          <.pill
            :if={month == @focus}
            cell={cell}
            id={@assignable && "pill-#{@id}-#{key}"}
          />
          <.quiet :if={month != @focus} cell={cell} current={@current} />
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
      aria-label={pill_label(@status, @cell)}
      phx-click="open_popover"
      phx-value-kind="pill"
      phx-value-category={@cell.category_id}
      phx-value-anchor={@id}
    >
      <.pill_content status={@status} cell={@cell} />
    </button>
    <span :if={!@id} class={["app-pill", pill_class(@status)]}>
      <.pill_content status={@status} cell={@cell} />
      <span :if={@status != :zero && @status.label} class="sr-only">{@status.label}</span>
    </span>
    """
  end

  attr :status, :any, required: true
  attr :cell, :any, required: true

  defp pill_content(%{status: :zero} = assigns), do: ~H"{Money.amount(0)}"

  defp pill_content(assigns) do
    ~H"""
    <.icon :if={@status.icon} name={@status.icon} />{Money.euros(@cell.available)}
    """
  end

  defp pill_class(:zero), do: "app-pill-zero"
  defp pill_class(%{tone: tone}), do: "app-pill-#{tone}"

  defp pill_label(status, cell) do
    state = if status != :zero && status.label, do: ", #{status.label}"
    "Verfügbar #{Money.euros(cell.available)}#{state}, Geld verschieben"
  end

  attr :cell, :any, required: true
  attr :current, Date, required: true

  defp quiet(assigns) do
    assigns = assign(assigns, :status, Status.quiet(assigns.cell, assigns.current))

    ~H"""
    <span class={quiet_class(@status.tone)}>
      <span :if={@status.dot} class="app-udot" title="unterfinanziert">
        <span class="sr-only">unterfinanziert</span>
      </span>{Money.amount(
        @cell.available
      )}
    </span>
    """
  end

  defp quiet_class(:muted), do: "app-zero"
  defp quiet_class(tone), do: tone_class(tone)

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
      <tr :for={row <- @rows} class="app-row app-inc">
        <td class="app-cat">
          <div class="app-catcell">
            <span class="app-emoji" aria-hidden="true"></span>
            <span class="app-catbtn">{row.payee || "Ohne Empfänger"}</span>
          </div>
        </td>
        <%= for value <- Enum.map(@months, &Map.get(row.amounts, &1, 0)) do %>
          <td class="app-ms"></td>
          <td class={["app-num", if(value == 0, do: "app-zero", else: "app-quiet")]}>
            {Money.amount(value)}
          </td>
          <td class="app-num app-quiet">
            <span class="app-alt">{Money.amount(value)}</span>
          </td>
        <% end %>
      </tr>
    </.group>
    """
  end
end
