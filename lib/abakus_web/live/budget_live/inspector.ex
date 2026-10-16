defmodule AbakusWeb.BudgetLive.Inspector do
  @moduledoc """
  The focus month's categories and the selected category: on desktop a dialog from the category's row with its
  name, target and deleting, on phones a sheet with the same parts after what is available (with the assignment)
  and auto-assign.

  `new/4` gathers what they show: every category, as the table shows them.
  """
  use AbakusWeb, :html

  import Abakus.Format, only: [month_name: 1, month_abbr: 1, month_year: 1]

  alias Abakus.Budget.{CategoryMonth, Month}
  alias Abakus.Money
  alias AbakusWeb.BudgetLive.{CategoryEditor, Components, Status, TargetForm, Window}

  defstruct [:month, :free, categories: [], selected: nil]

  @doc """
  The focus month among `months` (`Abakus.Budget.Month`s), with the selected category's id or nil. `categories`
  are the categories in budget order with their group and cell; `free` is what can be assigned without taking
  what later months have.
  """
  def new(groups, months, focus, selected_id) do
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

  @doc "The selected category's dialog on desktop: its name, target and note, and deleting it."
  def dialog(assigns) do
    assigns = assign(assigns, :entry, assigns.inspector.selected)

    ~H"""
    <div class="app-insp">
      <.month_line cell={@entry.cell} current={@current} />
      <CategoryEditor.category_name edit={@edit} autofocus />
      <.target_section cell={@entry.cell} form={@target_form} />
      <.note category={@entry.category} />
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
    doc: "`%{value, invalid}` for the assign field, which the table on phones does not have"

  @doc "The selected category's sheet on phones."
  def sheet(assigns) do
    assigns = assign(assigns, :entry, assigns.inspector.selected)

    ~H"""
    <div class="app-insp">
      <div id="inspector-head">
        <h2 id="inspector-name" class="app-insp-title truncate">{@entry.category.name}</h2>
        <.month_line cell={@entry.cell} current={@current} />
      </div>
      <.available_section
        cell={@entry.cell}
        previous={@entry.previous}
        category={@entry.category}
        assign={@assign}
      />
      <.overspent_hint :if={@entry.cell.available < 0} entry={@entry} />
      <.target_section cell={@entry.cell} form={@target_form} />
      <.auto_section
        key={key(@inspector)}
        category={@entry.category.id}
        underfunded={Status.open_need(@entry.cell)}
      />
      <CategoryEditor.category_name edit={@edit} />
      <.note category={@entry.category} />
      <CategoryEditor.category_delete edit={@edit} />
    </div>
    """
  end

  attr :cell, CategoryMonth, required: true
  attr :current, Date, required: true

  defp month_line(assigns) do
    ~H"""
    <p class="text-sm text-base-content/70">
      {month_year(@cell.month)}<span :if={@cell.month == @current}><.meta_sep />aktueller Monat</span>
    </p>
    """
  end

  attr :category, :any, required: true

  defp note(assigns) do
    ~H"""
    <section :if={present?(@category.note)} id="inspector-note">
      <.section_heading level={3}>Notiz</.section_heading>
      <p class="app-note text-sm">{@category.note}</p>
    </section>
    """
  end

  defp key(%__MODULE__{month: month}), do: Window.param(month.month)

  defp present?(text), do: is_binary(text) and String.trim(text) != ""

  defp cover(category, anchor) do
    JS.push("open_popover",
      value: %{kind: "cover", category: Integer.to_string(category.id), anchor: anchor}
    )
  end

  attr :key, :string, required: true
  attr :category, :integer, required: true
  attr :underfunded, :integer, required: true

  defp auto_section(assigns) do
    assigns = assign(assigns, :fill, auto(assigns.key, assigns.category, "underfunded"))

    ~H"""
    <section id="inspector-auto">
      <.section_heading level={3}>Auto-Verteilen</.section_heading>
      <ul class="app-acts">
        <li id="auto-underfunded" class="app-act">
          <span class="app-act-name">Unterfinanziert</span>
          <.amount value={@underfunded} class={@underfunded == 0 && "text-base-content/70"} />
          <.button
            :if={@underfunded > 0}
            size={:sm}
            aria-label="Unterfinanzierte füllen"
            phx-click={@fill}
          >
            Füllen
          </.button>
        </li>
      </ul>
    </section>
    """
  end

  defp auto(key, category, kind),
    do: JS.push("auto", value: %{month: key, category: to_string(category), kind: kind})

  attr :cell, CategoryMonth, required: true
  attr :previous, :any, required: true
  attr :category, :any, required: true
  attr :assign, :map, required: true

  defp available_section(assigns) do
    ~H"""
    <section id="inspector-available">
      <.section_heading level={3}>
        Verfügbar
        <:actions><Components.pill cell={@cell} /></:actions>
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
              numeric
              suffix="€"
              autocomplete="off"
              class="max-w-36"
              errors={if @assign.invalid, do: ["Kein gültiger Betrag"], else: []}
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

  attr :entry, :map, required: true

  defp overspent_hint(assigns) do
    ~H"""
    <.alert id="inspector-cover" tone={:error} title="Überzogen">
      {month_name(@entry.cell.month)} ist um
      <strong class="whitespace-nowrap">{Money.euros(-@entry.cell.available)}</strong>
      überzogen. Decke es aus „Zu verteilen“ oder einer anderen Kategorie.
      <:actions>
        <.button
          id={"cover-hint-#{@entry.category.id}"}
          size={:sm}
          phx-click={cover(@entry.category, "cover-hint-#{@entry.category.id}")}
        >
          Decken
        </.button>
      </:actions>
    </.alert>
    """
  end

  attr :cell, CategoryMonth, required: true
  attr :form, :any, required: true

  defp target_section(assigns) do
    ~H"""
    <section id="inspector-target">
      <.section_heading level={3}>
        Ziel
        <:actions :if={@cell.target && @cell.snoozed}>
          <.badge>pausiert</.badge>
        </:actions>
      </.section_heading>
      <TargetForm.editor :if={@form} form={@form} target={@cell.target} />
      <.target_view :if={!@form && @cell.target} cell={@cell} />
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

  defp target_view(assigns) do
    assigns =
      assign(assigns,
        head: Status.target_head(assigns.cell.target),
        status: Status.target_status(assigns.cell)
      )

    ~H"""
    <p class="text-sm font-medium">{elem(@head, 0)}</p>
    <p :if={elem(@head, 1)} class="text-sm text-base-content/70">{elem(@head, 1)}</p>
    <.alert :if={@cell.snoozed} tone={:neutral} class="mt-3">
      Im {month_name(@cell.month)} pausiert: das Ziel zählt diesen Monat nicht als unterfinanziert.
    </.alert>
    <.bar
      :if={!@cell.snoozed}
      id="target-status"
      class="mt-4"
      label={@status.title}
      value={round((@cell.progress || 0) * 100)}
      tone={@status.tone}
      target={Status.target_mark(@cell)}
      show_value
    />
    <.alert
      :if={!@cell.snoozed && @cell.underfunded > 0}
      id="target-rest"
      tone={:warning}
      class="mt-3"
    >
      Weise noch <strong class="whitespace-nowrap">{Money.euros(@cell.underfunded)}</strong>
      zu, um dein Ziel zu erreichen.
      <:actions>
        <.button id="target-assign" size={:sm} phx-click="assign_rest">Zuweisen</.button>
      </:actions>
    </.alert>
    <.description_list :if={!@cell.snoozed} class="mt-3">
      <:item :if={@cell.saved} label="Angespart">
        <span class="whitespace-nowrap">
          {Money.amount(@cell.saved)} von {Money.euros(@cell.target.amount)}
        </span>
      </:item>
      <:item label="Ziel diesen Monat"><.amount value={@cell.needed} /></:item>
    </.description_list>
    <div class="mt-4 flex flex-wrap gap-2">
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
end
