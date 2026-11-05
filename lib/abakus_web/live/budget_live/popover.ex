defmodule AbakusWeb.BudgetLive.Popover do
  @moduledoc """
  The list that covers an overspent category in the focus month, opened from its Verfügbar: where the money can
  come from, Zu verteilen first; choosing one covers as much as it holds. One shared Setzkasten `popover` anchored
  to the cell, a bottom sheet on phones.

  The state is `%{anchor, category_id, open}`. A closed popover stays rendered, so focus returns to its anchor.
  """
  use AbakusWeb, :html

  alias Abakus.{Money, Names}
  alias AbakusWeb.BudgetLive.Inspector

  @doc "Opens the popover for an overspent category at the anchor's element."
  def open(anchor, entry), do: %{anchor: anchor, category_id: entry.category.id, open: true}

  @doc """
  Where overspending can be covered from, as `{free, categories}`: what Zu verteilen holds while it is above zero
  (else nil), and the other categories with money, the most first, as `{id, name, available}`.
  """
  def sources(%Inspector{} = inspector, category_id) do
    categories =
      for %{category: category, cell: cell} <- inspector.categories,
          category.id != category_id,
          cell.available > 0 do
        {category.id, category.name, cell.available}
      end

    {if(inspector.free > 0, do: inspector.free), Enum.sort_by(categories, &elem(&1, 2), :desc)}
  end

  @doc "How much covering takes from the source: the overspending, as far as the source has."
  def cover_amount(entry, available), do: min(-entry.cell.available, available)

  attr :popover, :map, required: true
  attr :inspector, Inspector, required: true

  @doc "The popover, while its category is overspent."
  def editor(assigns) do
    entry = Inspector.find(assigns.inspector, assigns.popover.category_id)
    assigns = assign(assigns, :entry, entry && entry.cell.available < 0 && entry)

    ~H"""
    <.popover
      :if={@entry}
      id="popover"
      title={"#{Money.euros(-@entry.cell.available)} decken aus"}
      anchor={@popover.anchor}
      align={:end}
      show={@popover.open}
      layout={:list}
      on_cancel={JS.push("close_popover", value: %{anchor: @popover.anchor})}
    >
      <.source_list entry={@entry} sources={sources(@inspector, @entry.category.id)} />
    </.popover>
    """
  end

  attr :entry, :map, required: true
  attr :sources, :any, required: true

  defp source_list(assigns) do
    {free, categories} = assigns.sources

    assigns =
      assign(assigns,
        free: free,
        categories:
          for({id, name, available} <- categories, do: {id, Names.split_emoji(name), available})
      )

    ~H"""
    <.pick_list id="cover-sources">
      <:group :if={@free}>
        <.pick_item id="cover-from-rta" icon="inbox" on_click={cover(@entry, "rta")} autofocus>
          Zu verteilen<:trailing><.amount value={@free} tone /></:trailing>
        </.pick_item>
      </:group>
      <:group :if={@categories != []}>
        <.pick_item
          :for={{{id, {emoji, name}, available}, index} <- Enum.with_index(@categories)}
          id={"cover-from-#{id}"}
          on_click={cover(@entry, id)}
          autofocus={is_nil(@free) and index == 0}
        >
          <:leading>{emoji}</:leading>{name}
          <:trailing><.amount value={available} /></:trailing>
        </.pick_item>
      </:group>
      <:empty>Kein Geld in „Zu verteilen“ oder anderen Kategorien.</:empty>
    </.pick_list>
    """
  end

  defp cover(entry, from), do: JS.push("cover", value: %{category: entry.category.id, from: from})
end
