defmodule AbakusWeb.CategoryOptions do
  @moduledoc """
  Categories as selects offer them, in the shape `Phoenix.HTML.Form.options_for_select/2` takes: Ready to Assign
  first as income, then the visible categories by group. Hidden categories (or those of hidden groups) show only
  where `keep` names them, so a transaction keeps a category hidden since.
  """

  alias Abakus.Categories

  def build(keep \\ []) do
    ready_to_assign = Categories.ready_to_assign!()

    groups =
      for group <- Categories.list_category_groups(),
          categories = Enum.filter(group.categories, &(visible?(group, &1) or &1.id in keep)),
          categories != [] do
        {group.name, Enum.map(categories, &{&1.name, &1.id})}
      end

    [{"Zu verteilen (Einnahme)", ready_to_assign.id} | groups]
  end

  defp visible?(group, category), do: not group.hidden and not category.hidden

  @doc "The category ids among the options."
  def ids(options) do
    Enum.flat_map(options, fn
      {_group, categories} when is_list(categories) -> Enum.map(categories, &elem(&1, 1))
      {_name, id} -> [id]
    end)
  end
end
