defmodule AbakusWeb.BudgetLive.Popover do
  @moduledoc """
  The popovers of the budget, in the focus month: the available pill's, with "Decken" (while overspent) and
  "Verschieben"; covering a category from the overspent list; and "In eine Kategorie …" from Verteilen, which
  assigns Zu verteilen to a category. One shared Setzkasten `popover`, anchored to what opened it.

  The state is `%{kind: :pill | :cover | :pick, anchor, category_id, mode: :cover | :move, from, error, open}`
  (`from`: the chosen source to cover from); a pick also has the category and amount it suggests. A closed popover stays rendered, so focus returns to its anchor.
  """
  use AbakusWeb, :html

  import AbakusWeb.Format

  alias Abakus.Money
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
      amount: suggested && Money.amount(pick_amount(suggested, inspector.free)),
      error: nil,
      open: true
    }
  end

  def open(kind, anchor, entry, _inspector) do
    mode = if kind == :cover or entry.cell.available < 0, do: :cover, else: :move

    %{
      kind: kind,
      anchor: anchor,
      category_id: entry.category.id,
      mode: mode,
      from: nil,
      error: nil,
      open: true
    }
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

  @doc "The popover."
  def editor(assigns) do
    entry = Inspector.find(assigns.inspector, assigns.popover[:category_id])

    assigns =
      assign(assigns, entry: entry, title: title(assigns.popover, entry, assigns.inspector))

    ~H"""
    <.popover
      :if={@title}
      id="popover"
      title={@title}
      anchor={@popover.anchor}
      align={:end}
      show={@popover.open}
      on_cancel={JS.push("close_popover", value: %{anchor: @popover.anchor})}
    >
      <.pill_content
        :if={@popover.kind == :pill}
        popover={@popover}
        entry={@entry}
        inspector={@inspector}
      />
      <.cover_form
        :if={@popover.kind == :cover}
        entry={@entry}
        inspector={@inspector}
        from={@popover.from}
        error={@popover.error}
      />
      <.pick_content :if={@popover.kind == :pick} popover={@popover} inspector={@inspector} />
    </.popover>
    """
  end

  defp title(%{kind: :pick}, _entry, inspector),
    do: "In eine Kategorie verteilen · #{month_name(inspector.month.month)}"

  defp title(_popover, nil, _inspector), do: nil
  defp title(%{kind: :pill}, entry, _inspector), do: entry.category.name
  defp title(%{kind: :cover}, entry, _inspector), do: "Überzug decken · #{entry.category.name}"

  defp pill_content(assigns) do
    ~H"""
    <div class="flex items-center justify-between gap-2">
      <p class="text-sm text-base-content/70">{month_year(@entry.cell.month)}</p>
      <Components.pill cell={@entry.cell} />
    </div>
    <.segmented
      :if={@entry.cell.available < 0}
      id="popover-mode"
      mode={:button}
      label="Aktion"
      size={:sm}
      block
      class="mt-3"
      value={@popover.mode}
      options={[{"Decken", "cover"}, {"Verschieben", "move"}]}
      phx-click="popover_mode"
    />
    <.cover_form
      :if={@popover.mode == :cover}
      entry={@entry}
      inspector={@inspector}
      from={@popover.from}
      error={@popover.error}
    />
    <.move_form
      :if={@popover.mode == :move}
      entry={@entry}
      inspector={@inspector}
      error={@popover.error}
    />
    <.button
      id="popover-details"
      variant={:link}
      size={:sm}
      class="mt-2 px-0"
      phx-click={
        JS.focus(to: "##{@popover.anchor}")
        |> JS.push("select", value: %{category: to_string(@entry.category.id)})
      }
    >
      Kategorie bearbeiten <.icon name="chevron-right" />
    </.button>
    """
  end

  attr :entry, :map, required: true
  attr :inspector, Inspector, required: true
  attr :from, :string, default: nil, doc: "the chosen source; the first one when nil"
  attr :error, :string, default: nil

  defp cover_form(assigns) do
    sources = sources(assigns.inspector, assigns.entry.category.id)
    source = Enum.find(sources, List.first(sources), &(elem(&1, 0) == assigns.from))
    assigns = assign(assigns, sources: sources, source: source)

    ~H"""
    <form id="cover-form" class="mt-2" phx-change="cover_change" phx-submit="cover">
      <input type="hidden" name="category" value={@entry.category.id} />
      <%= if @sources == [] do %>
        <p class="text-sm">Kein Geld in „Zu verteilen“ oder anderen Kategorien.</p>
      <% else %>
        <.combobox
          id="cover-from"
          name="from"
          label={"Decke #{Money.euros(-@entry.cell.available)} aus"}
          value={elem(@source, 0)}
          placeholder="Kategorie suchen"
          options={
            for {value, label, available} <- @sources,
                do: %{label: label, value: value, available: available}
          }
          errors={List.wrap(@error)}
        >
          <:option :let={option}>
            <span class="min-w-0 flex-1 truncate">{option.label}</span>
            <.amount value={option.available} class="shrink-0" />
          </:option>
        </.combobox>
        <p id="cover-after" class="mt-2 flex justify-between gap-2 text-sm">
          <span class="text-base-content/70">{after_label(@source)}</span>
          <.amount value={after_cover(@entry, @source)} />
        </p>
        <.popover_actions submit_id="cover-submit" submit="Decken" autofocus />
      <% end %>
    </form>
    """
  end

  defp after_label({"rta", _label, _available}), do: "Zu verteilen danach"
  defp after_label({_id, label, _available}), do: "#{label} danach"

  defp after_cover(entry, {_id, _label, available}),
    do: available - cover_amount(entry, available)

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
    <form id="move-form" class="mt-2" phx-submit="move">
      <input type="hidden" name="category" value={@entry.category.id} />
      <.input
        id="move-amount"
        autofocus
        name="amount"
        label="Betrag"
        value={Money.amount(@amount)}
        suffix="€"
        numeric
        autocomplete="off"
        errors={List.wrap(@error)}
      />
      <.segmented
        id="move-direction"
        mode={:radio}
        name="direction"
        label="Richtung"
        size={:sm}
        block
        class="mt-2"
        value={if @give, do: "to", else: "from"}
        options={[{"Abgeben an", "to"}, {"Holen aus", "from"}]}
      />
      <.combobox
        id="move-other"
        name="other"
        label="Andere Kategorie"
        hide_label
        value="rta"
        placeholder="Kategorie suchen"
        options={[{"📥 Zu verteilen", "rta"} | category_options(@inspector, @entry.category.id)]}
      />
      <.popover_actions submit_id="move-submit" submit="Verschieben" />
    </form>
    """
  end

  attr :popover, :map, required: true
  attr :inspector, Inspector, required: true

  defp pick_content(assigns) do
    ~H"""
    <form id="pick-form" phx-change="pick_change" phx-submit="pick">
      <.combobox
        id="pick-category"
        name="category"
        label="Kategorie"
        value={@popover.category_id}
        placeholder="Kategorie suchen"
        options={category_options(@inspector, nil)}
      />
      <.input
        id="pick-amount"
        autofocus
        name="amount"
        label="Betrag"
        value={@popover.amount}
        suffix="€"
        numeric
        autocomplete="off"
        help={"Frei zu verteilen: #{Money.euros(@inspector.free)}"}
        errors={List.wrap(@popover.error)}
      />
      <.popover_actions submit_id="pick-submit" submit="Zuweisen" />
    </form>
    """
  end

  attr :submit_id, :string, required: true
  attr :submit, :string, required: true
  attr :autofocus, :boolean, default: false

  defp popover_actions(assigns) do
    ~H"""
    <div class="mt-3 flex justify-end gap-2">
      <.button size={:sm} phx-click="close_popover">Abbrechen</.button>
      <.button
        id={@submit_id}
        type="submit"
        variant={:primary}
        size={:sm}
        autofocus={@autofocus}
      >
        {@submit}
      </.button>
    </div>
    """
  end

  defp category_options(inspector, skip) do
    inspector.categories
    |> Enum.reject(&(&1.category.id == skip))
    |> Enum.chunk_by(& &1.group.id)
    |> Enum.map(fn [first | _] = entries ->
      {first.group.name, Enum.map(entries, &{&1.category.name, &1.category.id})}
    end)
  end
end
