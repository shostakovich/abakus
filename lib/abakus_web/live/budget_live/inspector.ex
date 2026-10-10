defmodule AbakusWeb.BudgetLive.Inspector do
  @moduledoc """
  The inspector beside the budget, as in YNAB but slimmed down. With nothing selected it shows the focus month: how
  Zu verteilen adds up, the summary with the month's need, the overspent categories with "Decken", auto-assign
  and what later months have assigned. With a category selected it shows that category in the focus month: what is
  available and how, a hint to cover overspending, the target card, auto-assign for it and its note.

  `new/4` gathers what it shows: every category, as the table shows them.
  """
  use AbakusWeb, :html

  import AbakusWeb.Format

  alias Abakus.Budget.{CategoryMonth, Month}
  alias AbakusWeb.BudgetLive.{CategoryEditor, Components, Status, TargetForm, Window}

  defstruct [:month, :free, categories: [], overspent: [], future: [], assigned: 0, selected: nil]

  @doc """
  The inspector for the focus month among `months` (`Abakus.Budget.Month`s), with the selected category's id or
  nil. `categories` are the categories in budget order with their group and cell; `free` is what can be
  assigned without taking what later months have.
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
      overspent: overspent(month, categories),
      future:
        for(m <- months, Date.after?(m.month, focus), m.assigned != 0, do: {m.month, m.assigned}),
      assigned: categories |> Enum.map(& &1.cell.assigned) |> Enum.sum(),
      selected: selected(categories, selected_id, by_month[Date.shift(focus, month: -1)])
    }
  end

  defp overspent(month, categories) do
    uncategorised =
      if month.uncategorised.available < 0,
        do: [%{category: nil, cell: month.uncategorised}],
        else: []

    uncategorised ++ for(entry <- categories, entry.cell.available < 0, do: entry)
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
  attr :back, :boolean, default: true, doc: "whether a selected category leads back to the month"
  attr :edit, :map, default: nil, doc: "the selected category's open rename or delete popover"

  @doc "What the inspector shows: the month, or the selected category."
  def body(%{inspector: %{selected: nil}} = assigns) do
    ~H"""
    <h2 class="app-insp-title mb-3">{month_year(@inspector.month.month)}</h2>
    <.ready_card month={@inspector.month} />
    <.summary_card month={@inspector.month} />
    <.overspent_card :if={@inspector.overspent != []} overspent={@inspector.overspent} />
    <.auto_card
      key={key(@inspector)}
      underfunded={@inspector.month.underfunded}
      assigned={@inspector.assigned}
      confirm={"Alle Zuweisungen im #{month_name(@inspector.month.month)} zurücksetzen?"}
    />
    <.future_card month={@inspector.month} future={@inspector.future} />
    """
  end

  def body(assigns) do
    assigns = assign(assigns, :entry, assigns.inspector.selected)

    ~H"""
    <button
      :if={@back}
      id="inspector-back"
      type="button"
      class="btn btn-sm btn-link px-0 mb-2 text-decoration-none"
      phx-click="deselect"
    >
      <.icon name="back" class="app-icon-sm" /> Monatsübersicht
    </button>
    <div class="d-flex align-items-center gap-2 mb-1">
      <h2 id="inspector-name" class="app-insp-title mb-0 me-auto text-truncate">
        {@entry.category.name}
      </h2>
      <div class="dropdown">
        <button
          id="edit-category"
          type="button"
          class="btn btn-sm btn-light"
          aria-label="Umbenennen oder löschen"
          title="Umbenennen oder löschen"
          aria-expanded={to_string(@edit != nil)}
          phx-click="edit_open"
          phx-value-edit="category"
          phx-value-category={@entry.category.id}
        >
          <.icon name="pencil" class="app-icon-sm" />
        </button>
        <CategoryEditor.popover :if={@edit} edit={@edit} align_end />
      </div>
    </div>
    <div class="small text-body-secondary mb-2">
      {month_year(@entry.cell.month)}{if @entry.cell.month == @current, do: " · aktueller Monat"}
    </div>
    <.available_card cell={@entry.cell} previous={@entry.previous} />
    <.overspent_hint :if={@entry.cell.available < 0} entry={@entry} />
    <.target_card cell={@entry.cell} form={@target_form} />
    <.auto_card
      key={key(@inspector)}
      category={@entry.category.id}
      underfunded={Status.open_need(@entry.cell)}
      assigned={@entry.cell.assigned}
    />
    <section :if={present?(@entry.category.note)} id="inspector-note" class="card mb-3">
      <div class="card-header">Notiz</div>
      <div class="card-body small app-note">{@entry.category.note}</div>
    </section>
    """
  end

  defp key(%__MODULE__{month: month}), do: Window.param(month.month)

  defp present?(text), do: is_binary(text) and String.trim(text) != ""

  attr :month, Month, required: true

  defp ready_card(assigns) do
    assigns = assign(assigns, :ready, Status.ready(assigns.month))

    ~H"""
    <section class="card mb-3">
      <div class="card-header">Zu verteilen</div>
      <div class="card-body small d-flex flex-column gap-1">
        <.line
          :for={line <- Status.calculation(@month)}
          label={line.label}
          value={line.value}
          class={line.class}
        />
        <.line
          label={elem(@ready, 1)}
          value={@month.ready_to_assign_shown}
          class={["fw-bold border-top pt-1", elem(@ready, 0)]}
        />
        <ul :if={@month.uncovered != []} class="app-uncovered list-unstyled text-danger mt-2 mb-0">
          <li :for={line <- Status.uncovered(@month)} class="d-flex align-items-start gap-1">
            <.icon name="alert" class="app-icon-sm mt-1" /><span>{line}</span>
          </li>
        </ul>
      </div>
    </section>
    """
  end

  attr :month, Month, required: true

  defp summary_card(assigns) do
    ~H"""
    <section class="card mb-3">
      <div class="card-header">Zusammenfassung</div>
      <div class="card-body small d-flex flex-column gap-1">
        <.line label="Übrig aus Vormonat" value={@month.carried} />
        <.line label="Zugewiesen" value={@month.assigned} />
        <.line label="Aktivität" value={@month.activity} />
        <.line label="Verfügbar" value={@month.available} class="fw-bold border-top pt-1" />
        <div class="mt-2 fw-semibold">Monatsbedarf</div>
        <.line label="Ziele" value={@month.needed} />
        <.line
          :if={@month.underfunded > 0}
          label="Noch offen"
          value={@month.underfunded}
          class="text-warning-emphasis fw-semibold"
        />
      </div>
    </section>
    """
  end

  attr :overspent, :list, required: true

  defp overspent_card(assigns) do
    ~H"""
    <section id="inspector-overspent" class="card mb-3 border-danger">
      <div class="card-header text-danger d-flex align-items-center gap-2">
        <.icon name="alert" class="app-icon-sm" />{length(@overspent)} überzogen
      </div>
      <div class="list-group list-group-flush app-overs">
        <div
          :for={%{category: category, cell: cell} <- @overspent}
          id={"overspent-#{category_key(category)}"}
          class="list-group-item d-flex align-items-center gap-2 small"
        >
          <span class="flex-grow-1 app-min-w-0 text-truncate">
            {if category, do: category.name, else: "Nicht kategorisiert"}
          </span>
          <span class="app-overs-act">
            <Components.pill cell={cell} />
            <button
              :if={category}
              id={"cover-#{category.id}"}
              type="button"
              class="btn btn-sm btn-outline-danger"
              phx-click="open_popover"
              phx-value-kind="cover"
              phx-value-category={category.id}
              phx-value-anchor={"cover-#{category.id}"}
            >
              Decken
            </button>
            <.link
              :if={!category}
              navigate={~p"/accounts/all"}
              class="btn btn-sm btn-outline-danger"
              title="Buchungen ohne Kategorie zuordnen"
            >
              Zuordnen
            </.link>
          </span>
        </div>
      </div>
    </section>
    """
  end

  defp category_key(nil), do: "uncategorised"
  defp category_key(category), do: category.id

  attr :key, :string, required: true
  attr :category, :any, default: nil, doc: "the category's id, nil for all"
  attr :underfunded, :integer, required: true
  attr :assigned, :integer, required: true
  attr :confirm, :string, default: nil

  defp auto_card(assigns) do
    ~H"""
    <section id="inspector-auto" class="card mb-3">
      <div class="card-header">Auto-Verteilen</div>
      <div class="list-group list-group-flush small">
        <button
          id="auto-underfunded"
          type="button"
          class="list-group-item list-group-item-action d-flex justify-content-between gap-2"
          disabled={@underfunded == 0}
          phx-click="auto"
          phx-value-kind="underfunded"
          phx-value-month={@key}
          phx-value-category={@category}
        >
          <span>Unterfinanziert</span><span class="app-q text-nowrap">{euros(@underfunded)}</span>
        </button>
        <button
          id="auto-reset"
          type="button"
          class="list-group-item list-group-item-action d-flex justify-content-between gap-2"
          disabled={@assigned == 0}
          phx-click="auto"
          phx-value-kind="reset"
          phx-value-month={@key}
          phx-value-category={@category}
          data-confirm={@confirm}
        >
          <span>Zuweisung zurücksetzen</span><span class="app-q text-nowrap">{euros(@assigned)}</span>
        </button>
      </div>
    </section>
    """
  end

  attr :month, Month, required: true
  attr :future, :list, required: true

  defp future_card(assigns) do
    ~H"""
    <section id="inspector-future" class="card mb-3">
      <div class="card-header">Künftige Monate</div>
      <div class="card-body small d-flex flex-column gap-1">
        <.line label="Insgesamt" value={@month.assigned_in_future} class="fw-semibold" />
        <.line :for={{month, assigned} <- @future} label={month_year(month)} value={assigned} />
        <span :if={@future == []} class="text-body-secondary">Nichts im Voraus verteilt.</span>
      </div>
    </section>
    """
  end

  attr :cell, CategoryMonth, required: true
  attr :previous, :any, required: true

  defp available_card(assigns) do
    ~H"""
    <section id="inspector-available" class="card mb-3">
      <div class="card-header d-flex align-items-center justify-content-between">
        <span>Verfügbar</span>
        <Components.pill cell={@cell} />
      </div>
      <div class="card-body small d-flex flex-column gap-1">
        <.line label="Übrig aus Vormonat" value={@cell.carried} />
        <.line
          :if={@previous && @previous.available < 0}
          label={"Überzug im #{month_short(@previous.month)}"}
          value={@previous.available}
          class="text-danger"
        />
        <.line label="Zugewiesen" value={@cell.assigned} />
        <.line label="Aktivität" value={@cell.activity} />
      </div>
    </section>
    """
  end

  attr :entry, :map, required: true

  defp overspent_hint(assigns) do
    ~H"""
    <section id="inspector-cover" class="card mb-3 border-danger">
      <div class="card-header text-danger">Überzogen</div>
      <div class="card-body small">
        <p class="mb-2">
          {month_name(@entry.cell.month)} ist um
          <strong class="text-nowrap">{euros(-@entry.cell.available)}</strong>
          überzogen. Decke es aus „Zu verteilen“ oder einer anderen Kategorie.
        </p>
        <button
          id={"cover-hint-#{@entry.category.id}"}
          type="button"
          class="btn btn-sm btn-danger w-100"
          phx-click="open_popover"
          phx-value-kind="cover"
          phx-value-category={@entry.category.id}
          phx-value-anchor={"cover-hint-#{@entry.category.id}"}
        >
          Decken
        </button>
      </div>
    </section>
    """
  end

  attr :cell, CategoryMonth, required: true
  attr :form, :any, required: true

  defp target_card(assigns) do
    ~H"""
    <section id="inspector-target" class="card mb-3">
      <div class="card-header d-flex align-items-center gap-2">
        <.icon name="target" class="app-icon-sm" />Ziel
        <span :if={@cell.target && @cell.snoozed} class="badge text-bg-secondary ms-auto">
          pausiert
        </span>
      </div>
      <div class="card-body small">
        <TargetForm.editor :if={@form} form={@form} target={@cell.target} />
        <.target_view :if={!@form && @cell.target} cell={@cell} />
        <div :if={!@form && !@cell.target}>
          <p class="text-body-secondary">
            Kein Ziel. Ein Ziel sagt dir, wie viel diese Kategorie jeden Monat braucht.
          </p>
          <button
            id="target-edit"
            type="button"
            class="btn btn-sm btn-primary w-100"
            phx-click="edit_target"
          >
            Ziel festlegen
          </button>
        </div>
      </div>
    </section>
    """
  end

  attr :cell, CategoryMonth, required: true

  defp target_view(assigns) do
    assigns =
      assign(assigns,
        head: Status.target_head(assigns.cell.target),
        line: Status.target_line(assigns.cell)
      )

    ~H"""
    <div class="fw-semibold">{elem(@head, 0)}</div>
    <div :if={elem(@head, 1)} class="text-body-secondary">{elem(@head, 1)}</div>
    <div :if={@cell.snoozed} class="alert alert-secondary text-center py-2 mt-2 mb-2">
      Im {month_name(@cell.month)} pausiert: das Ziel zählt diesen Monat nicht als unterfinanziert.
    </div>
    <div :if={!@cell.snoozed} id="target-status" class="my-2">
      <Components.target_bar line={@line} />
      <div class="mt-1">{@line.title}</div>
    </div>
    <.line
      :if={!@cell.snoozed && @cell.saved}
      label="Angespart"
      text={"#{amount(@cell.saved)} von #{euros(@cell.target.amount)}"}
    />
    <div
      :if={!@cell.snoozed && @cell.underfunded > 0}
      id="target-rest"
      class="alert alert-warning text-center py-2 my-2"
    >
      <div>
        Weise noch <strong class="text-nowrap">{euros(@cell.underfunded)}</strong>
        zu, um dein Ziel zu erreichen
      </div>
      <button
        id="target-assign"
        type="button"
        class="btn btn-sm btn-warning w-100 mt-2"
        phx-click="assign_rest"
      >
        Zuweisen
      </button>
    </div>
    <.line :if={!@cell.snoozed} label="Ziel diesen Monat" value={@cell.needed} />
    <.line :if={!@cell.snoozed} label="Zugewiesen" value={@cell.assigned} />
    <div class="d-flex gap-2 mt-2">
      <button
        id="target-snooze"
        type="button"
        class="btn btn-sm btn-outline-secondary"
        phx-click={if @cell.snoozed, do: "unsnooze", else: "snooze"}
      >
        {if @cell.snoozed, do: "Fortsetzen", else: "Pausieren"}
      </button>
      <button
        id="target-edit"
        type="button"
        class="btn btn-sm btn-light flex-grow-1"
        phx-click="edit_target"
      >
        Ziel bearbeiten
      </button>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :value, :integer, default: nil
  attr :text, :string, default: nil
  attr :class, :any, default: nil

  defp line(assigns) do
    ~H"""
    <div class={["d-flex justify-content-between gap-3", @class]}>
      <span class="text-truncate">{@label}</span>
      <span class="app-q text-nowrap">{@text || euros(@value)}</span>
    </div>
    """
  end
end
