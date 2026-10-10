defmodule AbakusWeb.BudgetLive.Popover do
  @moduledoc """
  The popovers of the budget, in the focus month: the available pill's, with "Decken" (while overspent) and
  "Verschieben"; covering a category from the overspent list; and "In eine Kategorie …" from Verteilen, which
  assigns Zu verteilen to a category. The `Popover` hook places it at its anchor (`assets/js/hooks/budget.js`).

  The state is `%{kind: :pill | :cover | :pick, anchor, category_id, mode: :cover | :move, error}`; a pick also
  has the category and amount it suggests.
  """
  use AbakusWeb, :html

  import AbakusWeb.Format

  alias AbakusWeb.BudgetLive.{Components, Inspector, Status}

  @doc "Opens a popover at the anchor's element; a pill opens on \"Decken\" while its category is overspent."
  def open(:pick, anchor, _entry, inspector) do
    suggested =
      Enum.find(inspector.categories, &(Status.open_need(&1.cell) > 0)) ||
        List.first(inspector.categories)

    %{
      kind: :pick,
      anchor: anchor,
      category_id: suggested && suggested.category.id,
      amount: suggested && amount(pick_amount(suggested, inspector.free)),
      error: nil
    }
  end

  def open(kind, anchor, entry, _inspector) do
    mode = if kind == :cover or entry.cell.available < 0, do: :cover, else: :move
    %{kind: kind, anchor: anchor, category_id: entry.category.id, mode: mode, error: nil}
  end

  @doc "What a pick suggests for a category: what its target still asks, as far as Zu verteilen reaches."
  def pick_amount(entry, free) do
    case Status.open_need(entry.cell) do
      0 -> free
      need -> min(need, free)
    end
  end

  @doc """
  Where overspending can be covered from: Zu verteilen while there is some, then the other categories with money,
  the most first. As `{value, label, available}`.
  """
  def sources(%Inspector{} = inspector, category_id) do
    rta = if inspector.free > 0, do: [{"rta", "📥 Zu verteilen", inspector.free}], else: []

    categories =
      for %{category: category, cell: cell} <- inspector.categories,
          category.id != category_id,
          cell.available > 0 do
        {Integer.to_string(category.id), category.name, cell.available}
      end

    rta ++ Enum.sort_by(categories, &elem(&1, 2), :desc)
  end

  @doc "How much covering takes from the source: the overspending, as far as the source has."
  def cover_amount(entry, available), do: min(-entry.cell.available, available)

  attr :popover, :map, required: true
  attr :inspector, Inspector, required: true

  @doc "The open popover."
  def popover(assigns) do
    assigns =
      assign(assigns, :entry, Inspector.find(assigns.inspector, assigns.popover[:category_id]))

    ~H"""
    <div
      id="popover"
      class="card shadow-lg app-pop"
      role="dialog"
      aria-labelledby="popover-title"
      data-anchor={@popover.anchor}
      phx-hook="Popover"
      phx-mounted={JS.ignore_attributes(["style"])}
      phx-click-away={JS.push("close_popover", value: %{anchor: @popover.anchor})}
      phx-window-keydown="close_popover"
      phx-key="Escape"
    >
      <div class="card-body">
        <.pill_content
          :if={@popover.kind == :pill}
          popover={@popover}
          entry={@entry}
          inspector={@inspector}
        />
        <.cover_content
          :if={@popover.kind == :cover}
          popover={@popover}
          entry={@entry}
          inspector={@inspector}
        />
        <.pick_content :if={@popover.kind == :pick} popover={@popover} inspector={@inspector} />
      </div>
    </div>
    """
  end

  defp pill_content(assigns) do
    ~H"""
    <div class="d-flex align-items-center gap-2 mb-1">
      <span id="popover-title" class="fw-semibold me-auto text-truncate">{@entry.category.name}</span>
      <Components.pill cell={@entry.cell} />
    </div>
    <div class="small text-body-secondary mb-2">{month_year(@entry.cell.month)}</div>
    <div
      :if={@entry.cell.available < 0}
      class="btn-group btn-group-sm w-100 mb-2"
      role="group"
      aria-label="Aktion"
    >
      <button
        :for={{mode, label} <- [cover: "Decken", move: "Verschieben"]}
        id={"popover-#{mode}"}
        type="button"
        class={["btn btn-outline-secondary", @popover.mode == mode && "active"]}
        aria-pressed={to_string(@popover.mode == mode)}
        phx-click="popover_mode"
        phx-value-mode={mode}
      >
        {label}
      </button>
    </div>
    <.cover_form
      :if={@popover.mode == :cover}
      entry={@entry}
      inspector={@inspector}
      error={@popover.error}
    />
    <.move_form
      :if={@popover.mode == :move}
      entry={@entry}
      inspector={@inspector}
      error={@popover.error}
    />
    <button
      id="popover-details"
      type="button"
      class="btn btn-sm btn-link px-0 mt-2 text-decoration-none"
      phx-click="select"
      phx-value-category={@entry.category.id}
    >
      Details und Ziel <.icon name="chevron" class="app-icon-sm" />
    </button>
    """
  end

  defp cover_content(assigns) do
    ~H"""
    <div id="popover-title" class="fw-semibold mb-2 text-truncate">
      Überzug decken · {@entry.category.name}
    </div>
    <.cover_form entry={@entry} inspector={@inspector} error={@popover.error} />
    """
  end

  attr :entry, :map, required: true
  attr :inspector, Inspector, required: true
  attr :error, :string, default: nil

  defp cover_form(assigns) do
    assigns = assign(assigns, :sources, sources(assigns.inspector, assigns.entry.category.id))

    ~H"""
    <form id="cover-form" class="d-flex flex-column gap-2" phx-submit="cover">
      <input type="hidden" name="category" value={@entry.category.id} />
      <%= if @sources == [] do %>
        <p class="small mb-0">Kein Geld in „Zu verteilen“ oder anderen Kategorien.</p>
      <% else %>
        <label class="small" for="cover-from">
          Decke <strong class="text-nowrap">{euros(-@entry.cell.available)}</strong> aus:
        </label>
        <select id="cover-from" name="from" class="form-select form-select-sm">
          <option :for={{value, label, available} <- @sources} value={value}>
            {label} ({euros(available)})
          </option>
        </select>
        <.popover_error error={@error} />
        <div class="d-flex justify-content-end gap-2">
          <button type="button" class="btn btn-sm" phx-click="close_popover">Abbrechen</button>
          <button id="cover-submit" type="submit" class="btn btn-sm btn-primary">Decken</button>
        </div>
      <% end %>
    </form>
    """
  end

  attr :entry, :map, required: true
  attr :inspector, Inspector, required: true
  attr :error, :string, default: nil

  defp move_form(assigns) do
    cell = assigns.entry.cell
    give = cell.available > 0

    assigns =
      assign(assigns,
        give: give,
        amount:
          cond do
            give -> cell.available
            cell.underfunded > 0 -> cell.underfunded
            true -> max(-cell.available, 0)
          end
      )

    ~H"""
    <form id="move-form" class="d-flex flex-column gap-2" phx-submit="move">
      <input type="hidden" name="category" value={@entry.category.id} />
      <div class="input-group input-group-sm">
        <input
          id="move-amount"
          name="amount"
          value={amount(@amount)}
          class={["form-control text-end app-q", @error && "is-invalid"]}
          inputmode="decimal"
          autocomplete="off"
          aria-label="Betrag"
        />
        <span class="input-group-text">€</span>
      </div>
      <div class="btn-group btn-group-sm w-100" role="group" aria-label="Richtung">
        <%= for {value, label} <- [{"to", "Abgeben an"}, {"from", "Holen aus"}] do %>
          <input
            type="radio"
            class="btn-check"
            name="direction"
            id={"move-#{value}"}
            value={value}
            checked={value == "to" == @give}
          />
          <label class="btn btn-outline-secondary" for={"move-#{value}"}>{label}</label>
        <% end %>
      </div>
      <select
        id="move-other"
        name="other"
        class="form-select form-select-sm"
        aria-label="Andere Kategorie"
      >
        <option value="rta">📥 Zu verteilen</option>
        <.category_options inspector={@inspector} skip={@entry.category.id} />
      </select>
      <.popover_error error={@error} />
      <div class="d-flex justify-content-end gap-2">
        <button type="button" class="btn btn-sm" phx-click="close_popover">Abbrechen</button>
        <button id="move-submit" type="submit" class="btn btn-sm btn-primary">Verschieben</button>
      </div>
    </form>
    """
  end

  attr :popover, :map, required: true
  attr :inspector, Inspector, required: true

  defp pick_content(assigns) do
    ~H"""
    <div id="popover-title" class="fw-semibold mb-2">
      In eine Kategorie verteilen · {month_name(@inspector.month.month)}
    </div>
    <form id="pick-form" class="d-flex flex-column gap-2" phx-change="pick_change" phx-submit="pick">
      <select
        id="pick-category"
        name="category"
        class="form-select form-select-sm"
        aria-label="Kategorie"
      >
        <.category_options inspector={@inspector} selected={@popover.category_id} />
      </select>
      <div class="input-group input-group-sm">
        <input
          id="pick-amount"
          name="amount"
          value={@popover.amount}
          class={["form-control text-end app-q", @popover.error && "is-invalid"]}
          inputmode="decimal"
          autocomplete="off"
          aria-label="Betrag"
        />
        <span class="input-group-text">€</span>
      </div>
      <div class="form-text mt-0">Frei zu verteilen: {euros(@inspector.free)}</div>
      <.popover_error error={@popover.error} />
      <div class="d-flex justify-content-end gap-2">
        <button type="button" class="btn btn-sm" phx-click="close_popover">Abbrechen</button>
        <button id="pick-submit" type="submit" class="btn btn-sm btn-primary">Zuweisen</button>
      </div>
    </form>
    """
  end

  attr :inspector, Inspector, required: true
  attr :skip, :any, default: nil
  attr :selected, :any, default: nil

  defp category_options(assigns) do
    assigns =
      assign(
        assigns,
        :groups,
        assigns.inspector.categories
        |> Enum.reject(&(&1.category.id == assigns.skip))
        |> Enum.chunk_by(& &1.group.id)
      )

    ~H"""
    <optgroup :for={[first | _] = entries <- @groups} label={first.group.name}>
      <option
        :for={%{category: category} <- entries}
        value={category.id}
        selected={category.id == @selected}
      >
        {category.name}
      </option>
    </optgroup>
    """
  end

  attr :error, :string, default: nil

  defp popover_error(assigns) do
    ~H"""
    <div :if={@error} class="invalid-feedback d-block mt-0">{@error}</div>
    """
  end
end
