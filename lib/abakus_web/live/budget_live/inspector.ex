defmodule AbakusWeb.BudgetLive.Inspector do
  @moduledoc """
  The focus month's categories and the selected category: on desktop a dialog from the category's row with its
  name as the title, its target and deleting, on phones a sheet with the same parts and what is available (with the
  assignment). Covering is not here: an overspent Verfügbar opens its own list (`Popover`).

  `new/5` gathers what they show: every category, as the table shows them.
  """
  use AbakusWeb, :html

  import Abakus.Format, only: [month_abbr: 1, month_year: 1]

  alias Abakus.Budget.{CategoryMonth, Month}
  alias Abakus.Money
  alias AbakusWeb.BudgetLive.{CategoryEditor, Components, Status, TargetForm, Window}

  defstruct [:month, :free, budgeting: false, categories: [], selected: nil]

  @doc """
  The focus month among `months` (`Abakus.Budget.Month`s), with the selected category's id or nil. `categories`
  are the categories in budget order with their group and cell; `free` is what can be assigned without taking
  what later months have; `budgeting` whether the month is being budgeted (`Status.budgeting?/2`).
  """
  def new(groups, months, focus, current, selected_id) do
    by_month = Map.new(months, &{&1.month, &1})
    %Month{} = month = by_month[focus]
    cells = Map.new(month.categories, &{&1.category_id, &1})

    categories =
      for group <- groups, category <- group.categories do
        %{group: group, category: category, cell: cells[category.id]}
      end

    %__MODULE__{
      month: month,
      free: Month.free(month),
      budgeting: Status.budgeting?(month, current),
      categories: categories,
      selected: selected(categories, selected_id, by_month[Date.shift(focus, month: -1)])
    }
  end

  defp selected(categories, id, previous_month) do
    case Enum.find(categories, &(&1.category.id == id)) do
      nil ->
        nil

      entry ->
        previous = previous_month && Enum.find(previous_month.categories, &(&1.category_id == id))
        Map.put(entry, :previous, previous)
    end
  end

  @doc "The category with the id, with its group and cell, or nil."
  def find(%__MODULE__{categories: categories}, id),
    do: Enum.find(categories, &(&1.category.id == id))

  attr :inspector, __MODULE__, required: true
  attr :current, Date, required: true
  attr :target_form, :any, required: true, doc: "the target editor's form while it is open"
  attr :edit, :map, required: true, doc: "the selected category's `CategoryEditor` state"

  @doc "The selected category's dialog on desktop: its name as the title, its target, and deleting it."
  def dialog(assigns) do
    assigns = assign(assigns, :entry, assigns.inspector.selected)

    ~H"""
    <div class="app-insp">
      <.head entry={@entry} current={@current} />
      <.target_section cell={@entry.cell} free={@inspector.free} form={@target_form} />
      <CategoryEditor.category_delete edit={@edit} />
    </div>
    """
  end

  attr :inspector, __MODULE__, required: true
  attr :current, Date, required: true
  attr :target_form, :any, required: true, doc: "the target editor's form while it is open"
  attr :edit, :map, required: true, doc: "the selected category's `CategoryEditor` state"

  attr :assign, :map,
    required: true,
    doc: "`%{value, error}` for the assign field, which the table on phones does not have"

  @doc "The selected category's sheet on phones."
  def sheet(assigns) do
    assigns = assign(assigns, :entry, assigns.inspector.selected)

    ~H"""
    <div class="app-insp">
      <.head entry={@entry} current={@current} />
      <.available_section
        cell={@entry.cell}
        budgeting={@inspector.budgeting}
        previous={@entry.previous}
        category={@entry.category}
        assign={@assign}
      />
      <.target_section cell={@entry.cell} free={@inspector.free} form={@target_form} />
      <CategoryEditor.category_delete edit={@edit} />
    </div>
    """
  end

  attr :entry, :map, required: true
  attr :current, Date, required: true

  defp head(assigns) do
    ~H"""
    <div id="category-head">
      <p class="text-sm text-base-content/70">
        {month_year(@entry.cell.month)}<span :if={@entry.cell.month == @current}><.meta_sep />aktueller Monat</span>
      </p>
    </div>
    """
  end

  attr :cell, CategoryMonth, required: true
  attr :budgeting, :boolean, required: true
  attr :previous, :any, required: true
  attr :category, :any, required: true
  attr :assign, :map, required: true

  defp available_section(assigns) do
    ~H"""
    <section id="inspector-available">
      <.section_heading level={3}>
        Verfügbar
        <:actions><Components.available cell={@cell} budgeting={@budgeting} /></:actions>
      </.section_heading>
      <.description_list>
        <:item label="Übrig aus Vormonat"><.amount value={@cell.carried} /></:item>
        <:item
          :if={@previous && @previous.available < 0}
          label={"Überzug im #{month_abbr(@previous.month)}"}
        >
          <.amount value={@previous.available} class="text-error-ink" />
        </:item>
        <:item label="Zugewiesen">
          <form id="panel-assign-form" class="app-panel-assign" phx-submit="assign">
            <input type="hidden" name="category" value={@category.id} />
            <input type="hidden" name="month" value={Window.param(@cell.month)} />
            <.input
              id="panel-assign"
              name="value"
              label="Zugewiesen"
              hide_label
              value={@assign.value}
              data-saved={Money.amount(@cell.assigned)}
              numeric
              inputmode="text"
              autocapitalize="off"
              spellcheck="false"
              suffix="€"
              autocomplete="off"
              class="max-w-36"
              errors={List.wrap(@assign.error)}
              phx-blur="assign"
              phx-value-category={@category.id}
              phx-value-month={Window.param(@cell.month)}
            />
          </form>
        </:item>
        <:item label="Aktivität"><.amount value={@cell.activity} /></:item>
      </.description_list>
    </section>
    """
  end

  attr :cell, CategoryMonth, required: true

  attr :free, :integer,
    required: true,
    doc: "what Zu verteilen has free for the target's Zuweisen"

  attr :form, :any, required: true

  defp target_section(assigns) do
    ~H"""
    <section id="inspector-target">
      <.section_heading level={3}>Ziel</.section_heading>
      <TargetForm.editor :if={@form} form={@form} target={@cell.target} />
      <.target_view :if={!@form && @cell.target} cell={@cell} free={@free} />
      <div :if={!@form && !@cell.target}>
        <p class="text-sm text-base-content/70">
          Kein Ziel. Ein Ziel sagt dir, wie viel diese Kategorie jeden Monat braucht.
        </p>
        <.button id="target-edit" size={:sm} icon="target" class="mt-3" phx-click="edit_target">
          Ziel festlegen
        </.button>
      </div>
    </section>
    """
  end

  attr :cell, CategoryMonth, required: true
  attr :free, :integer, required: true

  defp target_view(assigns) do
    assigns =
      assign(assigns,
        status: Status.target_status(assigns.cell),
        progress: Status.target_progress(assigns.cell),
        to_assign: Status.to_assign(assigns.cell, assigns.free)
      )

    ~H"""
    <p id="target-head" class="text-sm font-medium">{Status.target_head(@cell.target)}</p>
    <.bar
      :if={@progress}
      id="target-progress"
      class="mt-2"
      label={@progress}
      value={round((@cell.progress || 0) * 100)}
      tone={bar_tone(@status.tone)}
      target={Status.target_mark(@cell)}
      hide_label
    />
    <div class="mt-1.5 flex flex-wrap items-center justify-between gap-x-4 gap-y-1 text-sm">
      <span :if={@progress} id="target-saved" class="tabular-nums">{@progress}</span>
      <span
        id="target-status"
        class={[
          "flex items-center gap-1.5",
          @progress && "ms-auto",
          Components.tone_class(@status.tone)
        ]}
      >
        <.icon :if={@status.icon} name={@status.icon} />{@status.text}
      </span>
    </div>
    <div class="mt-4 flex flex-wrap gap-2">
      <.button
        :if={@cell.available >= 0 && @to_assign > 0}
        id="target-assign"
        size={:sm}
        phx-click="assign_rest"
      >
        {Money.euros(@to_assign)} zuweisen
      </.button>
      <.button
        id="target-snooze"
        size={:sm}
        phx-click={if @cell.snoozed, do: "unsnooze", else: "snooze"}
      >
        {if @cell.snoozed, do: "Fortsetzen", else: "Pausieren"}
      </.button>
      <.button id="target-edit" size={:sm} icon="pencil" phx-click="edit_target">
        Ziel bearbeiten
      </.button>
    </div>
    """
  end

  defp bar_tone(:muted), do: :neutral
  defp bar_tone(tone), do: tone
end
